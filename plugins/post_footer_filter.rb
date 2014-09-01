#
# post_footer_filter.rb
# Append every post some footer infomation like original url 
# Kevin Lynx
# 09.01.2014
#
require 'octopress-hooks'

module AppendFooterFilter
  def self.append(post)
     author = post.site.config['author']
     url = post.site.config['url']
     pre = post.site.config['original_url_pre']
     post.content + %Q[<p class='post-footer'>
            #{pre or "original link:"}
            <a href='#{post.full_url}'>#{post.full_url}</a><br/>
            written by <a href='#{url}'>#{author}</a>
            &nbsp;posted at <a href='#{url}'>#{url}</a>
            </p>]
  end 

  class PostFilters < Octopress::Hooks::Post
    def pre_render(post)
      post.content = AppendFooterFilter::append(post)
    end
  end
end

