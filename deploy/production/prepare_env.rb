# frozen_string_literal: true

# Standalone operator CLI; Rails and its translation framework are not loaded.
# rubocop:disable I18n/RailsI18n/DecorateString, Rails/Present

# Run with the existing installation's bundle so dotenv parsing matches it.
require 'dotenv'

abort 'Usage: prepare_env.rb SOURCE_ENV DESTINATION_ENV' unless ARGV.length == 2

source, destination = ARGV
values = Dotenv.parse(source)

# Compose's raw env_file format preserves $, quotes and backslashes verbatim.
# Multiline values cannot be represented by this format.
abort 'Multiline environment values require manual configuration.' if values.values.any? { |value| value.match?(/[\r\n]/) }

# URL settings can override the separate DB fields and TLS policy.
abort 'Review DATABASE_URL / REPLICA_DATABASE_URL before preparing production.' if values.values_at('DATABASE_URL', 'REPLICA_DATABASE_URL').any? { |value| value && !value.empty? }
abort 'This deployment requires S3_ENABLED=true.' unless values['S3_ENABLED'] == 'true'

File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
  values.each { |key, value| file.puts "#{key}=#{value}" }
end

puts 'Runtime environment file created; secret values were not printed.'

# rubocop:enable I18n/RailsI18n/DecorateString, Rails/Present
