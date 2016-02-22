require 'nokogiri'
require 'yaml'
require 'typhoeus'

#TODO report/doi/eml/{scope}/{identifier}/{revision}
#curl -i -X GET https://pasta.lternet.edu/package/report/doi/eml/knb-lter-lno/1/1

class PastaList
  attr_accessor :url
  attr_accessor :upload

  def initialize(production=nil)
    if File.exists?('credentials.yaml')
      credentials = File.open('credentials.yaml') {|y| YAML::load(y)}
      @user       = "uid=#{credentials['username']},o=LTER,dc=ecoinformatics,dc=org:#{credentials['password']}"
    end

    @server     = 'https://pasta.lternet.edu'
  end

  def list
    response = Typhoeus.get("#{@server}/package/eml/knb-lter-kbs",
                            :userpwd=> @user)
    response.body.each_line do |id|
      id = id.to_i
      docs = Typhoeus.get("#{@server}/package/eml/knb-lter-kbs/#{id}", :userpwd=> @user)
      docs.body.each_line do |i|
        doi_resp = Typhoeus.get("#{@server}/package/doi/eml/knb-lter-kbs/#{id}/#{i}", :userpwd=> @user)
        eml_resp= Typhoeus.get("#{@server}/package/metadata/eml/knb-lter-kbs/#{id}/#{i}", :userpwd=> @user)
        eml = Nokogiri::XML(eml_resp.body)
        dataset_title = eml.xpath("//dataset/title").text

        number_of_datatables = eml.xpath("//dataset/dataTable").count
        data = 0
        datatables = eml.xpath("//dataset/dataTable").each do |table|
          header_lines = table.xpath("physical/dataFormat/textFormat/numHeaderLines").text.to_i
          footer_lines = table.xpath("physical/dataFormat/textFormat/numFooterLines").text.to_i
          url = table.xpath("physical/distribution/online/url").text
          downloaded_file = File.open 'huge.dat', 'wb'
          request = Typhoeus::Request.new(url)
          request.on_headers do |response|
              if response.code != 200
                    raise "Request failed"
                      end
          end
          request.on_body do |chunk|
              downloaded_file.write(chunk)
          end
          request.on_complete do |response|
            downloaded_file.close
            # Note that response.body is ""
          end
          request.run
          wc_data_lines = `wc huge.dat`
          data_lines = wc_data_lines.split[0].to_i
          data = data + (data_lines - header_lines - footer_lines)
        end
        tables = "tables"
        if number_of_datatables == 0
          tables = "table"
        end
        puts "#{dataset_title} #{number_of_datatables} #{tables}, #{data} records #{doi_resp.body}"
      end
    end
  end

end

list = PastaList.new
list.list
