require 'main'
require './lib/pasta'

Main {
  argument 'url'
  option('p')       { description 'to use the production server' }
  option('s')       { description 'submit the datapackage if there are no errors' }
  option('cache')   { description 'cache data locally, this assumes that there is a webserver running that serves the "data" sub-directry of the current directory'}
  option('delete_all') { description 'delete all datapackages' }
  option('debug')   { description 'print debugging statements' }
  option('timeout') {
    argument :optional
    cast :integer
    default 30
    description 'timeout in minutes'
  }

  def run
    if params['debug'].given?
      Typhoeus::Config.verbose = true
    end
    pusher = PastaEval.new(params['p'])

    if params['delete_all'].given?
      pusher.delete_all
    else
      if params['s'].given?
        pusher.upload = true
      end
      if params['cache'].given?
        pusher.cache = true
      end

      pusher.url = params['url'].value
      pusher.evaluate(params['timeout'].value)
    end
    puts "\done, now get back to work!"
  end
}
