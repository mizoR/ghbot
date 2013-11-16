require 'cinch'
require 'octokit'
require 'googl'
require 'ghbot/version'

module Ghbot
  class Notifier

    def self.plugin(options={})
      @plugin ||= Class.new do |c|
        include Cinch::Plugin

        @interval = options[:interval] || 60
        @channel  = options[:channel]
        @client   = Octokit::Client.new(
          :login    => options[:login],
          :password => options[:password]
        )

        timer @interval, :method => :run

        def run
          if !locked?
            begin
              lock && notify
            ensure
              unlock
            end
          end
        end

        private

        def notify
          @last_retrieved_at ||= Time.now - 60 * 60

          notifications = client.notifications(:all => true)
          notifications.sort_by(&:updated_at).each do |notification|
            updated_at = notification.updated_at
            next if updated_at <= @last_retrieved_at

            subject    = notification[:subject]
            repository = notification[:repository]
            latest_comment = subject.rels[:latest_comment].get.data
            issue_id       = latest_comment[:number] || begin
              issue = latest_comment.rels[:issue]
              issue = (issue && issue.get.data)
              issue && issue[:number]
            end

            if issue_id
              html_url =  "https://github.com/#{repository.full_name}/issues/#{issue_id}"
              html_url << "#issuecomment-#{latest_comment.id}"
              html_url = Googl.shorten(html_url).short_url
            end

            send(
              :title    => subject.title,
              :body     => latest_comment.body,
              :html_url => html_url,
              :commented_on =>  "#{subject.type.downcase} of #{repository.full_name}",
              :commented_by => latest_comment.user.login
            )

            @last_retrieved_at = updated_at
          end
        end

        def send(params={})
          view = \
            "\x02\x0301,00#{params[:title]}\017 - #{params[:html_url]}\n" \
            "\x0314 commented on #{params[:commented_on]} "               \
            "by #{params[:commented_by]}\017\n"                           \
            "#{params[:body]}\n\n "
          Channel(channel).send(view)
        end

        def locked?
          !!@is_locked
        end

        def lock
          @is_locked = true
        end

        def unlock
          @is_locked = false
        end

        def client
          self.class.instance_eval {@client}
        end

        def channel
          self.class.instance_eval {@channel}
        end
      end
    end
  end
end
