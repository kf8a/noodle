require 'main'
require './lib/pasta'

Main {
  argument 'url'
  option('p')       { description 'to use the production server' }
  option('s')       { description 'submit the datapackage if there are no errors' }
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
    if params['s'].given?
      puts "submit is not yet implemented"
    end

    pusher = PastaEval.new(params['p'])
    pusher.url = params['url'].value
    pusher.evaluate(params['timeout'].value)
    puts "done, now get back to work!"
  end
}
