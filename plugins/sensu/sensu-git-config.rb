#!/usr/bin/env ruby
#!/opt/sensu/embedded/bin/ruby
#
# sensu-git-config is a plugin for sensu that lets you update your sensu config via git.
# You can manage your plugins, handlers and conf.d directory with this plugin.
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'git'
require 'json'

class UpdateSensuConfig < Sensu::Plugin::Check::CLI

  option :repo,
    :short => '-g',
    :long => '--git-repo=VALUE',
    :description => 'Git Repo to load config from'

  option :ignore,
    :short => '-i',
    :long => '--ignore-deps',
    :description => 'Do not alert if executed dependencies do not return code 0',
    :boolean => true,
    :default => false

  option :branch,
    :short => '-b',
    :long => '--git-branch=VALUE',
    :description => 'Git branch to use',
    :default => "master"

  option :base,
    :short => '-s',
    :long => '--sensu-base=VALUE',
    :description => 'Sensu base path',
    :default => "/etc/sensu"


  if config[:repo].nil?
    begin
      config[:repo] = JSON.parse(File.open("#{config[:base]}/config.json").read)
    rescue Exception => e
      critical "Git repo was not set, or could not be found in /etc/sensu/config.json"
    end
  else
    if File.exists?("#{config[:base]}/git-config")
      g = Git.open("#{config[:base]}/git-config")
      g.checkout(config[:branch])
      g.fetch
      g.merge("origin/#{config[:branch]}")
    else
      g = Git.clone(options[:git_config_repo], "#{config[:base]}/git-config")
      g.checkout(config[:branch])

      unless File.exists?("/etc/sensu/conf.d")
        File.symlink("#{config[:base]}/git-config/conf.d", "#{config[:base]}/conf.d")
      end

      unless File.exists?("/etc/sensu/plugins")
        File.symlink("#{config[:base]}/git-config/plugins", "#{config[:base]}/plugins")
      end

      unless File.exists?("/etc/sensu/handlers")
        File.symlink("#{config[:base]}/git-config/handlers", "#{config[:base]}/handlers")
      end

      dep_run_counter = 0
      dep_run_output = ""

      if File.directory?("#{config[:base]}/git-config/deps.d")
        Dir.glob("#{config[:base]}/git-config/deps.d/**/**").each do |file|
          next if File.directory?(file)

          IO.popen("#{file} 2>&1") do |cmd|
            dep_run_output = "#{file} executed: #{cmd.read}"
          end

          exit_code = $?.exitstatus
          dep_run_counter += 1

          if !config[:ignore] && exit_code != 0
            critical "A dependency exe: #{dep_run_output}"
          end
        end
      end
      ok "Git repo was updated and #{dep_run_counter} dependencies were executed."
    end
  end
end
