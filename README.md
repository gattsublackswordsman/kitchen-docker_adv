# <a name="title"></a> Kitchen::DockerAdv

A Test Kitchen Driver for DockerAdv.

## <a name="requirements"></a> Requirements

**TODO:** document any software or library prerequisites that are required to
use this driver. Implement the `#verify_dependencies` method in your Driver
class to enforce these requirements in code, if possible.

## <a name="installation"></a> Installation and Setup

Please read the [Driver usage][driver_usage] page for more details.

## <a name="config"></a> Configuration

**TODO:** Write descriptions of all configuration options

### <a name="config-require-chef-omnibus"></a> require\_chef\_omnibus

Determines whether or not a Chef [Omnibus package][chef_omnibus_dl] will be
installed. There are several different behaviors available:

* `true` - the latest release will be installed. Subsequent converges
  will skip re-installing if chef is present.
* `latest` - the latest release will be installed. Subsequent converges
  will always re-install even if chef is present.
* `<VERSION_STRING>` (ex: `10.24.0`) - the desired version string will
  be passed the the install.sh script. Subsequent converges will skip if
  the installed version and the desired version match.
* `false` or `nil` - no chef is installed.

The default value is unset, or `nil`.

## <a name="development"></a> Development

* Source hosted at [GitHub][repo]
* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## <a name="authors"></a> Authors

Created by [Sean Porter][author] (<portertech@gmail.com>)

maintained by [Gattsu] (<gattsu.blackswordsman@gmail.com>)

## <a name="license"></a> License

Apache 2.0 (see [LICENSE][license])


[author]:           https://github.com/gattsublackswordsman
[issues]:           https://github.com/gattsublackswordsman/kitchen-docker_adv/issues
[license]:          https://github.com/gattsublackswordsman/kitchen-docker_adv/blob/master/LICENSE
[repo]:             https://github.com/gattsublackswordsman/kitchen-docker_adv
[driver_usage]:     http://docs.kitchen-ci.org/drivers/usage
[chef_omnibus_dl]:  http://www.getchef.com/chef/install/