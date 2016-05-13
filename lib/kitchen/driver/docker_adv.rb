# -*- encoding: utf-8 -*-
#
# Copyright (C) 2014, Sean Porter
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen'
require 'json'
require 'uri'
require File.join(File.dirname(__FILE__), 'docker', 'erb')

module Kitchen

  module Driver

    # DockerAdv driver for Kitchen.
    #
    # @author Gattsu <Gattsu@gmail.com>
    class DockerAdv < Kitchen::Driver::SSHBase

      default_config :binary,        'docker'
      default_config :socket,        'unix:///var/run/docker.sock'
      default_config :privileged,    true
      default_config :capadd,        true
      default_config :module,        '1'
      default_config :branch,        'trunk'
      default_config :regression,    'V0.0.0'
      default_config :environment,   'integration'
      default_config :use_cache,     true
      default_config :remove_images, false
      default_config :run_command,   '/usr/sbin/sshd -D -o UseDNS=no -o UsePAM=no -o UsePrivilegeSeparation=no -o PidFile=/tmp/sshd.pid'
      default_config :username,      'kitchen'
      default_config :password,      'kitchen'
      default_config :tls,           false
      default_config :tls_verify,    false
      default_config :tls_cacert,    nil
      default_config :tls_cert,      nil
      default_config :tls_key,       nil
      default_config :svn_base,      'https://svn.domain.com/svn/proj1/'
      default_config :svn_user,      'svnuser'
      default_config :svn_pwd,       'svnpwd'

      default_config :use_sudo do |driver|
        !driver.remote_socket?
      end

      default_config :image do |driver|
        driver.default_image
      end

      default_config :platform do |driver|
        driver.default_platform
      end

      default_config :disable_upstart, true

      def verify_dependencies
        run_command("#{config[:binary]} > /dev/null", :quiet => true)
        rescue
          raise UserError,
          'You must first install the Docker CLI tool http://www.docker.io/gettingstarted/'
      end

      def default_image
        platform, release = instance.platform.name.split('-')
        if platform == "centos" && release
          release = "centos" + release.split('.').first
        end
        release ? [platform, release].join(':') : platform
      end

      def default_platform
        instance.platform.name.split('-').first
      end

      def create(state)
        state[:image_id] = build_image(state) unless state[:image_id]
        state[:container_id] = run_container(state) unless state[:container_id]
        state[:hostname] = remote_socket? ? socket_uri.host : 'localhost'
        state[:port] = container_ssh_port(state)
        wait_for_sshd(state[:hostname], nil, :port => state[:port])
      end

      def destroy(state)
        rm_container(state) if container_exists?(state)
        if config[:remove_images] && state[:image_id]
          rm_image(state)
        end
      end

      def remote_socket?
        config[:socket] ? socket_uri.scheme == 'tcp' : false
      end

      protected

      def socket_uri
        URI.parse(config[:socket])
      end

      def docker_command(cmd, options={})
        docker = config[:binary].dup
        docker << " -H #{config[:socket]}" if config[:socket]
        docker << " --tls" if config[:tls]
        docker << " --tlsverify" if config[:tls_verify]
        docker << " --tlscacert=#{config[:tls_cacert]}" if config[:tls_cacert]
        docker << " --tlscert=#{config[:tls_cert]}" if config[:tls_cert]
        docker << " --tlskey=#{config[:tls_key]}" if config[:tls_key]
        run_command("#{docker} #{cmd}", options.merge(:quiet => !logger.debug?))
      end

      def build_dockerfile
        from = "FROM #{config[:image]}"
        platform = case config[:platform]
        when 'debian', 'ubuntu'
          disable_upstart = <<-eos
            RUN dpkg-divert --local --rename --add /sbin/initctl
            RUN ln -sf /bin/true /sbin/initctl
          eos
          packages = <<-eos
            ENV DEBIAN_FRONTEND noninteractive
            RUN apt-get update
            RUN apt-get install -y sudo openssh-server curl lsb-release
          eos
          config[:disable_upstart] ? disable_upstart + packages : packages
        when 'rhel', 'centos'
          <<-eos
            RUN yum clean all
            RUN yum install -y sudo openssh-server openssh-clients which curl
            RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N ''
            RUN ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N ''
          eos
        when 'arch'
          <<-eos
            RUN pacman -Syu --noconfirm
            RUN pacman -S --noconfirm openssh sudo curl
            RUN ssh-keygen -A -t rsa -f /etc/ssh/ssh_host_rsa_key
            RUN ssh-keygen -A -t dsa -f /etc/ssh/ssh_host_dsa_key
          eos
        else
          raise ActionFailed,
          "Unknown platform '#{config[:platform]}'"
        end
        username = config[:username]
        password = config[:password]
        base = <<-eos
          RUN useradd -d /home/#{username} -m -s /bin/bash #{username}
          RUN echo #{username}:#{password} | chpasswd
          RUN echo '#{username} ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
        eos
        custom = ''
        Array(config[:provision_command]).each do |cmd|
          custom << "RUN #{cmd}\n"
        end
        [from, platform, base, custom].join("\n")
      end

      def dockerfile
        if config[:dockerfile]
          template = IO.read(File.expand_path(config[:dockerfile]))
          context = DockerERBContext.new(config.to_hash)
          ERB.new(template).result(context.get_binding)
        else
          build_dockerfile
        end
      end

      def parse_image_id(output)
        output.each_line do |line|
          if line =~ /image id|build successful|successfully built/i
            return line.split(/\s+/).last
          end
        end
        raise ActionFailed,
        'Could not parse Docker build output for image ID'
      end

      def build_image(state)
        cmd = "build"
        cmd << " --no-cache" unless config[:use_cache]
        cmd << " --build-arg module=#{config[:module]}" if config[:module]
        cmd << " --build-arg branch=#{config[:branch]}" if config[:branch]
        cmd << " --build-arg regression=#{config[:regression]}" if config[:regression]
        cmd << " --build-arg environment=#{config[:environment]}" if config[:environment]
        cmd << " --build-arg svn_base=#{config[:svn_base]}" if config[:svn_base]
        cmd << " --build-arg svn_user=#{config[:svn_user]}" if config[:svn_user]
        cmd << " --build-arg svn_pwd=#{config[:svn_pwd]}" if config[:svn_pwd]
        cmd << " --build-arg proxy_user=#{config[:proxy_user]}" if config[:proxy_user]
        cmd << " --build-arg proxy_pwd=#{config[:proxy_pwd]}" if config[:proxy_pwd]
        output = docker_command("#{cmd} -", :input => dockerfile)
        parse_image_id(output)
      end

      def parse_container_id(output)
        container_id = output.chomp
        unless [12, 64].include?(container_id.size)
          raise ActionFailed,
          'Could not parse Docker run output for container ID'
        end
        container_id
      end

      def build_run_command(image_id)
        cmd = "run -d -p 22"
        Array(config[:forward]).each {|port| cmd << " -p #{port}"}
        Array(config[:dns]).each {|dns| cmd << " -dns #{dns}"}
        Array(config[:volume]).each {|volume| cmd << " -v #{volume}"}
        Array(config[:volumes_from]).each {|container| cmd << " --volumes-from #{container}"}
        cmd << " -h #{config[:hostname]}" if config[:hostname]
        cmd << " -m #{config[:memory]}" if config[:memory]
        cmd << " -c #{config[:cpu]}" if config[:cpu]
        cmd << " --privileged"
        cmd << " --cap-add ALL"
        cmd << " -e http_proxy='#{config[:http_proxy]}'" if config[:http_proxy]
        cmd << " -p 3000:3000" if config[:rails]
        cmd << " -e https_proxy='#{config[:https_proxy]}'" if config[:https_proxy]
        cmd << " -e module=#{config[:module]}" 
        cmd << " -e branch=#{config[:branch]}"
        cmd << " -e regression=#{config[:regression]}"
        cmd << " -e environment=#{config[:environment]}" 
        cmd << " -e svn_base=#{config[:svn_base]}"
        cmd << " -e svn_user=#{config[:svn_user]}"
        cmd << " -e svn_pwd=#{config[:svn_pwd]}"
        cmd << " -e proxy_user=#{config[:proxy_user]}"
        cmd << " -e proxy_pwd=#{config[:proxy_pwd]}"
        cmd << " #{image_id} #{config[:run_command]}"
        cmd
      end

      def run_container(state)
        cmd = build_run_command(state[:image_id])
        output = docker_command(cmd)
        parse_container_id(output)
      end

      def inspect_container(state)
        container_id = state[:container_id]
	if container_id
          docker_command("inspect #{container_id} " + %q[| awk -F"=" '$1 !~ /svn_user|svn_pwd|proxy_user|proxy_pwd|http_proxy|https_proxy/ {print $0}; $1 ~ /svn_user|svn_pwd|proxy_user|proxy_pwd|http_proxy|https_proxy/ {print $1 "=*****\","}'])
        end
      end

      def container_exists?(state)
        !!inspect_container(state) rescue false
      end

      def parse_container_ssh_port(output)
        begin
          info = Array(::JSON.parse(output)).first
          ports = info['NetworkSettings']['Ports'] || info['HostConfig']['PortBindings']
          ssh_port = ports['22/tcp'].detect {|port| port['HostIp'] == '0.0.0.0'}
          ssh_port['HostPort'].to_i
        rescue
          raise ActionFailed,
          'Could not parse Docker inspect output for container SSH port'
        end
      end

      def container_ssh_port(state)
        output = inspect_container(state)
        parse_container_ssh_port(output)
      end

      def rm_container(state)
        container_id = state[:container_id]
        docker_command("stop #{container_id}")
        docker_command("rm -f #{container_id}")
      end

      def rm_image(state)
        image_id = state[:image_id]
        docker_command("rmi #{image_id}")
      end
    end
  end
end
