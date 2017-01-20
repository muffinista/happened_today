#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'chatterbot/dsl'

require 'json'
require 'date'
require 'net/http'

require 'wikipedia'
require "open-uri"
require 'tempfile'


#debug_mode
verbose

# calling bot here kickstarts the initialization process
bot
bot.config.delete(:db_uri)

bot.config[:event_index] ||= 0
bot.config[:date_index] ||= 0

def valid_url?(u)
  result = begin
             URI.parse(u)
             true
           rescue StandardError => e
             false
           end

  result
end

def save_to_tempfile(url)
  puts "LOAD #{url}"
  
  uri = URI.parse(url)
  ext = [".", uri.path.split(/\./).last].join("")

  dest = File.join "/tmp", Dir::Tmpname.make_tmpname(['list', ext], nil)

  puts "#{url} -> #{dest}"

  open(dest, 'wb') do |file|
    file << open(url).read
  end

  # if the image is too big, let's lower the quality a bit
  if File.size(dest) > 5_000_000
    `mogrify -quality 65% #{dest}`
  end

  dest
end

def filter_images(list)
  puts list.inspect
  list.reject { |l| l =~ /.svg$/ || ! valid_url?(l) }
end


day = Time.now

# we will call srand here so that we resort our data the same way
# each time.  i'm lazy and don't feel like writing the data out randomized
day -= (day.hour * 3600 + day.min * 60 + day.sec)
srand(day.to_i)

# grab data from the API if we don't have it already
data_file = "data/#{day.strftime("%m-%d")}.json"

if ! File.exist?(data_file)
  data = Net::HTTP.get(URI.parse('http://history.muffinlabs.com/date'))
  File.open(data_file, 'w') {|f| f.write(data) }
  
  bot.config[:event_index] = 0
else
  data = IO.read(data_file).force_encoding("UTF-8")
end

data = JSON.parse(data)
tmp = data['data']['Events'].sort_by { rand }.reject { |e| 
  twt = "#{e["year"]}: #{e["text"]}"
  twt.size > 140 or twt.size < 30
}

if bot.config[:date_index] != day.to_i
  bot.config[:event_index] = 0
  bot.config[:date_index] = day.to_i
end

media = nil

# :event_index will track our offset into the events array
if tmp.size > bot.config[:event_index]
  e = tmp[bot.config[:event_index]]
  puts e.inspect
  txt = "#{e["year"]}: #{e["text"]}"

  puts txt.length
  links = e["links"].sort_by { |l| -l["title"].length }
  puts links.inspect

  twitter_url_length = 22
  links.each { |l|
    txt = "#{txt} #{l["link"]}" if txt.length < 140 - twitter_url_length - 1

    if media.nil?
      page = Wikipedia.find(l["title"])
      image_urls = []

      if page.image_urls && ! page.image_urls.empty?       
        image_urls = filter_images(page.image_urls)
      end

      if ! image_urls.empty?
        image_url = image_urls.sample
        puts image_url

        media = File.new(save_to_tempfile(image_url))
        puts media
      end
      
    end
  }

  puts txt
end

bot.config[:event_index] = bot.config[:event_index] + 1

opts = {}
if ! media.nil?
  opts[:media] = media
end

puts "**** #{txt} #{opts.inspect}"
unless txt.nil?
  result = tweet txt, opts
  puts result.inspect
end
