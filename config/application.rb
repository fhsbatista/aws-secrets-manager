require_relative "boot"

require "rails/all"

initialize_aws_secrets_manager

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AwsSecretsManager
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
  end
end

def initialize_aws_secrets_manager
  #Source: https://anonoz.github.io/tech/2018/12/29/aws-secrets-in-rails.html
  if ENV['AWS_REGION'] && !ENV['DISABLE_AWS_SECRETS']
    secrets_prefix = ENV['AWS_SECRETS_PREFIX'] || "app_1/#{ENV['RAILS_ENV']}"
    client = Aws::SecretsManager::Client.new(region: ENV['AWS_REGION'])
  
    # Fetch a list of all secrets stored under this AWS account.
    # Requires action "secretsmanager:ListSecrets" for "*" in IAM.
    secrets = client.list_secrets(max_results: 100).secret_list.select do |x|
      /^#{secrets_prefix}/.match(x.name)
    end.map do |x|
      [
        /^#{secrets_prefix}\/(.*)/.match(x.name).captures[0],
        client.get_secret_value(secret_id: x.name).secret_string
      ]
    end.to_h
  
    # This is a hack, it assumes there are no unsafe characters in the username,
    # password and just naively concatenate the attribute values together.
    #
    # Feel free to change the database scheme.
    database_info = secrets['database'] || ENV['DATABASE_URL']
    if database_info
      begin
        db = JSON.parse(database_info)
        ENV['DATABASE_URL'] = "postgres://#{db['username']}:#{db['password']}@#{db['host']}:#{db['port']}/#{db['dbname']}"
      rescue JSON::ParserError => e
        ENV['DATABASE_URL'] = database_info
      end
    end
  
    # `others` is always a json of key-value pairs to be loaded to top-level in ENV
    JSON.parse(secrets['others']).each_pair do |k, v|
      ENV["#{k}".underscore.upcase] = v
      puts "Loaded env var #{k.underscore.upcase} from `others`"
    end
  
    # Go through other secret kv pairs in the list. Only allow 1 layer nesting.
    # Assumes most secrets are stored in proper JSON format, if they aren't,
    # fetch as multiline strings.
    secrets.except('database', 'database_url', 'others').each_pair do |k, v|
      begin
        subsecrets = JSON.parse(v)
        subsecrets.each_pair do |kk, vv|
          ENV["#{k}_#{kk}".underscore.upcase] = vv
          puts "Loaded env var #{"#{k}_#{kk}".underscore.upcase}"
        end
      rescue JSON::ParserError => e
        ENV[k.underscore.upcase] = v
        puts "Loaded env var #{k.underscore.upcase}"
      end
    end
  
  elsif ENV['DISABLE_AWS_SECRETS']
    puts "DISABLE_AWS_SECRETS has been set. Secrets will not be loaded from AWS."
  
  elsif !ENV['AWS_REGION']
    puts "AWS_REGION not set. Secrets will not be loaded from AWS."
  
  end
end
