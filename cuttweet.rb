#!/usr/bin/env ruby
#coding: utf-8
# This program is free software. It comes without any warranty, to the extent
# permitted by applicable law. You can redistribute it and/or modify it under
# the terms of the Do What The Fuck You Want To Public License, Version 2, as
# published by Sam Hocevar. See http://sam.zoy.org/wtfpl/COPYING for more
# details.

if RUBY_VERSION < "1.9"
  $stderr.puts "WARNING: Running Ruby #{RUBY_VERSION}. This program needs Ruby 1.9."
end

require "readline"

$consumer_key = 'e7KrGMzfh3JSy2TxAur6gg'
$consumer_secret = 'PFFYZeM7ATvJGEeEZFfL9GGojHu06gKGJDgH7mSZZA'
$oauth_token = nil
$oauth_token_secret = nil

if ARGV.reject!{|i| i == '--help' or i == '-h' }
  puts "#{$0} [-a|--get-new-auth] [tweet]" 
  exit
elsif ARGV.reject!{|i| i == '-a' or i == '--get-new-auth' } or
  not ($oauth_token and $oauth_token_secret)
  require 'oauth'

  consumer = OAuth::Consumer.new(
          $consumer_key,
          $consumer_secret,
          {      
                  :site => 'http://twitter.com/',
                  :request_token_path => '/oauth/request_token',
                  :access_token_path => '/oauth/access_token',
                  :authorize_path => '/oauth/authorize'
          })

  request_token = consumer.get_request_token

  print "Visit #{request_token.authorize_url} in your browser " +
        "to authorize the app, then enter the PIN you are given: "
  pin = STDIN.readline.chomp
  access_token = request_token.get_access_token(:oauth_verifier => pin)

  $oauth_token = access_token.token
  $oauth_token_secret = access_token.secret

  code = File.read(__FILE__)
  code.sub!(/(?<=\$oauth_token = ).+/, "'#{$oauth_token}'")
  code.sub!(/(?<=\$oauth_token_secret = ).+/, "'#{$oauth_token_secret}'")
  File.open(__FILE__, 'w') {|f| f.print code }
elsif ARGV.reject!{|i| i == '-r' || i =~ /^rt$/i}
  $rt = true
end

if ARGV[0] =~ /^\d+$/
  $id = ARGV.shift.to_i
end

require 'twitter'
Twitter.configure do |config|
  config.consumer_key = $consumer_key
  config.consumer_secret = $consumer_secret
  config.oauth_token = $oauth_token
  config.oauth_token_secret = $oauth_token_secret
end
client = Twitter::Client.new
screen_name = client.verify_credentials['screen_name']

status = $id ? client.status($id) : nil

line = nil

if ARGV.empty? and not $rt
  editor = ENV["EDITOR"] || "vi"
  begin
    file = Tempfile.new("cuttweet")
    file.puts
    file.puts
    file.puts "# Tweet as @#{screen_name}"
    file.puts "# Answering @#{status[:user][:screen_name]}: #{status[:text]}" if status
    file.close
    system(editor, file.path)
    file.open
    tweet = file.readlines
    tweet.map!{|s| s.strip }
    tweet.reject!{|s| s =~ /^#/ or s.empty? }
    line = tweet.join(" ")
  ensure
    file.close
    file.unlink
  end
else
  line = ARGV.join(" ")
end

if $rt
  if not $id
    $stderr.puts "What do you want to RT?"
    exit
  end

  if not status
    $stderr.puts "Status #{$id} not found!"
    exit
  end

  if not line.strip.empty?
    $stderr.puts "Not supported yet!"
  else
    puts "#{status[:user][:screen_name]}: #{status[:text]}"
    print "Retweet as @#{screen_name}? [Y/n]: "
    if $stdin.gets and ($_.chomp.empty? or $_.chomp.downcase == "y")
      client.retweet($id)
    end
  end
  exit
end

start = line[/^(?:\s*@[a-zA-Z0-9_]+)+/]

line = (start ? line[start.length..-1] : line)
line.strip!
prefix = (start ? start + " " : "")
length = 140 - prefix.length

if not line or line.empty?
  $stderr.puts "Empty tweet!"
  exit
end

def cut str, len, *step
  div = str.scan(step[0])
  div.each{|i| i.strip!}
  
  marker = (step.length == 1 ? "..." : "")

  i = 0
  while div[i]
    len_real = len - (i > 0 ? marker.length : 0) - (div[i+1] ? marker.length : 0)
    if div[i].length > len_real
      if step[1..-1].empty?
        raise "Impossible to cut \"#{str}\" in #{len}-char blobs"
      end
      div[i] = cut div[i], len, *step[1..-1]
      div.flatten!
    else
      while div[i+1] and div[i].length + div[i+1].length + 1 <= len_real
        div[i] << " " << div.delete_at(i+1)
      end
    end
    div[i] = marker + div[i] if i > 0
    div[i] << marker if div[i+1]
    i += 1
  end
  return div
end

tweets = cut(line, length,
             /.+?(?:[\.\?\!]\s+|$)/,
             /.+?(?:[:,;]\s+|$)/,
             /.+?(?:\s+|$)/)

tweets.map!{|i| prefix + i }
tweets.each do |tweet|
  puts "-" * 20
  puts tweet
end
puts "-" * 20
print "Post #{tweets.length} tweets as @#{screen_name}? [Y/n]: "
if $stdin.gets and ($_.chomp.empty? or $_.chomp.downcase == "y")
  tweets.each do |tweet|
    client.update(tweet, { :in_reply_to_status_id => $id })
    print "."
  end
  puts
end

