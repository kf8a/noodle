require 'main'
require 'rest-client'
require 'nokogiri'
require 'open-uri'


class PastaPush 
  attr_accessor :url

  def run(production=nil)
    @server = 'https://pasta-s.lternet.edu'
    if production.given?
      @server = 'https://pasta.lternet.edu'
    end

    #get url
    doc = Nokogiri::XML(open(url))
    doc.xpath('//documentURL').each do |eml_url|
      eml_doc = Nokogiri::XML(open(eml_url))

      # try to evaluate
       
      puts eml_doc
    end
  end
end

Main {
  argument 'url'
  option('s') {
    description 'to use the staging server'
  }

  def run
    pusher = PastaPush.new
    pusher.url = params['url'].value
    pusher.run(params['p'])
  end
}
