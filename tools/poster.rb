#!/usr/bin/env ruby
#
# I write this script to post my personl blog codemacro.com posts to my cppblog.com/kevinlynx
# Kevin Lynx 8.7.2012
#
require 'nokogiri'
require 'open-uri'
require 'xmlrpc/client'
require 'yaml'
require 'rack/utils'

class MetaWeblogClient < XMLRPC::Client
  def initialize(username, password, host, url)
    super(host, url)
    @username = username
    @password = password
  end

  def getPost(post_id)
    call("metaWeblog.getPost", "#{post_id}", "#{@username}", "#{@password}")
  end

  def editPost(post_id, post, publish)
    call("metaWeblog.editPost", "#{post_id}", "#{@username}", "#{@password}", post, publish)
  end

  def newPost(post, publish)
    call("metaWeblog.newPost", "0", "#{@username}", "#{@password}", post, publish)
  end

  def getRecentPosts(number)
    call("metaWeblog.getRecentPosts", "0", "#{@username}", "#{@password}", number)
  end

  def newMediaObject(data)
    call("metaWeblog.newMediaObject", "0", "#{@username}", "#{@password}", data)
  end
end

def fix_img_url(content)
  content.search('img').map { |img| 
    if not img['src'].start_with?('http')
      img['src'] = 'http://codemacro.com' + img['src']
    end
  }
end

# get post title and content for an octopress post
def post_info(url)
  doc = Nokogiri::HTML(open(url))
  content = doc.css('div.entry-content')
  fix_img_url(content)
  title = doc.css('header h1.entry-title').inner_html
  categories = doc.css('a.category').collect do |link| link.content end
  return title, content.to_s, categories
end

def load_config(file)
  file = File.open(file)
  YAML::load(file)
end

def check_config(config)
    ['host', 'url', 'username', 'password'].each do |key|
      if config[key].nil? 
        return false
      end
    end
    return true
end

def new_post(api, url)
  title, content, categories = post_info(url)
  if title.nil? or content.nil?
    puts "get post info failed at #{url}\n"
    return
  end
  post = { :title => title, :description => content, :categories => categories }
  api.newPost(post, true)
  puts "new post #{title} in #{categories} done\n"
end

def edit_post(api, postid, url)
  title, content, categories = post_info(url)
  if title.nil? or content.nil?
    puts "get post info failed at #{url}\n"
    return
  end
  post = { :title => title, :description => content, :categories => categories }
  api.editPost(postid, post, true)
  puts "edit post #{title} in #{categories} done\n"
end

def dump4csdn(content, title)
  open('post.txt', 'w') { |f| f.puts content.to_s }
end

def fix_code(content)
  content.search('pre').map { |pre| 
    code = pre.at('code')
    pre['name'] = 'code'
    pre['class'] = 'plain'
    pre.inner_html = Rack::Utils::escape_html(code.text)
    if code['data-lang'] == 'c++'
      pre['class'] = 'cpp'
    elsif code['data-lang'] == 'java'
      pre['class'] = 'java'
    end
  }
end

def append_footer_css(content)
  footer = content.at('.post-footer')
  footer['style'] = %{
    font-size:80%;color:#888888;margin:5px;padding:5px 10px;border:1px solid #565656;
    border-top-color:#cbcbcb;border-left-color:#a5a5a5;border-right-color:#a5a5a5
  }
end

def load4csdn(url)
  doc = Nokogiri::HTML(open(url))
  content = doc.css('div.entry-content')
  title = doc.css('header h1.entry-title').inner_html
  fix_img_url(content)
  fix_code(content)
  append_footer_css(content)
  dump4csdn(content, title)
end

def main
  file = "rposter.yaml"
  config = load_config(file)
  if not check_config(config)
    puts "config file <#{file}> invalid.\n"
    print_config
    return
  end
  cmd = ARGV[0]
  api = MetaWeblogClient.new(config["username"], config["password"], config["host"], config["url"])
  if cmd == "new" 
    new_post(api, ARGV[1])
  elsif cmd == "edit"
    edit_post(api, ARGV[1], ARGV[2])
  elsif cmd == "csdn"
    load4csdn(ARGV[1])
  else
    puts "unknown command #{cmd}\n"
  end
end

def print_usage
  usage = %Q{
    Usage: poster cmd cmd-arg
        new post-url
        edit post-id post-url
    need a config file `rposter.yaml' at the same directory
  }
  puts usage
  print_config
end

def print_config
  config = %Q{
    Config sample:
        host: www.cppblog.com
        url: /kevinlynx/services/metaweblog.aspx
        username: kevinlynx
        password: xxxx
  }
  puts config
end

if ARGV.size == 0 
  print_usage
  exit
end
main

