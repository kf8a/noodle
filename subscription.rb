require 'typhoeus'
require 'yaml'
require 'main'

Main {
  argument 'url'
  option('scope') { description 'scope to subscribe to' }
  option('p')     { description 'use the production server' }


  def run 
    host = "pasta-s.lternet.edu"
    if params['p'].given?
      host = "pasta.lternet.edu"
    end

    credentials = File.open('credentials.yaml') {|y| YAML::load(y)}
    user        = "uid=#{credentials['username']},o=LTER,dc=ecoinformatics,dc=org:#{credentials['password']}"
    
    response = Typhoeus.post("https://#{host}/eventmanager/subscription/eml",
                             body: %Q{<subscription type="eml"><packageId>#{params['scope'].value}</packageId><url>#{params['url'].value}</url></subscription>},
                             userpwd: user,
                             headers: {'Content-Type' => "application/xml; charset=utf-8"})

    p response.body
    p response.code
  end
}
  

