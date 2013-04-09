require 'main'
require 'rest-client'
require 'nokogiri'
require 'open-uri'
require 'typhoeus'


class PastaEval
  attr_accessor :url

  def run(production=nil)
    @server = 'https://pasta-s.lternet.edu'
    if production.given?
      @server = 'https://pasta.lternet.edu'
    end

    #get url
    doc = Nokogiri::XML(open(url))
    doc.xpath('//documentURL').each do |eml_url|
      print "#{eml_url.text} "
      eml_doc = Nokogiri::XML(open(eml_url))

      info = eml_url.parent
      @scope = info.search('scope').text
      @identifier = info.search('identifier').text
      @rev = info.search('revision').text

      # try to evaluate
      response = Typhoeus.post("#{@server}/package/evaluate/eml",
                               :body  => eml_doc.to_s,
                               :headers => {'Content-Type' => "application/xml; charset=utf-8"})
      @transaction_id = response.response_body

      #poll for completion
      n = 0
      $stdout.sync = true
      loop do
        print '.'
        sleep 5
        response = Typhoeus.get("#{@server}/package/evaluate/report/eml/#{@scope}/#{@identifier}/#{@rev}/#{@transaction_id}")
        break if response.success?
        n += 1
        break if n > 200

        # check error message
        break if pasta_errors?
      end

      if @errors
        puts @errors
        @errors = nil
        next
      end

      if n > 200
        puts ' timeout'
        next
      end

      doc = Nokogiri::XML(response.response_body)
      File.write('response.xml',doc)

      print_summary(doc)

      $stdout.sync = false

      # remove valid checks
      doc.search('//qr:status[contains(text(), "valid")]/..').each do |node|
        node.remove
      end

      File.open("#{@scope}-#{@identifier}-#{@rev}",'w') do |file|
        file.write doc
      end
    end
  end

  def print_summary(doc)
    valids = doc.search('//qr:status[contains(text(), "valid")]')
    warns  = doc.search('//qr:status[contains(text(), "warn")]')
    infos  = doc.search('//qr:status[contains(text(), "info")]')
    errors = doc.search('//qr:status[contains(text(), "error")]')
    File.write('response.xml',doc)

    puts " valid: #{valids.count} info: #{infos.count} warn: #{warns.count} error: #{errors.count}"

    # [warns,errors].each do |problems|
    #   problems.each do |problem|
    #     description = problem.search('/qr:desscription').text
    #     expected    = problem.search('/qr:expected').text
    #     found       = problem.search('/qr:found').text
    #     puts description
    #     puts "expected: #{expected}, found: #{found}"
    #   end
    # end
  end

  def pasta_errors?
    response = Typhoeus.get("#{@server}/package/error/#{@scope}/#{@identifier}/#{@rev}/#{@transaction_id}")
    @errors = response.response_body if response.success?

    response.success?
  end

end

Main {
  argument 'url'
  option('p') { description 'to use the production server' }
  option('debug') { description 'print debugging statements' }

  def run
    if params['debug'].given?
      Typhoeus::Config.verbose = true
    end

    pusher = PastaEval.new
    pusher.url = params['url'].value
    pusher.run(params['p'])
  end
}
