# frozen_string_literal: true

require "aws-sdk-s3"

AWS_CLIENT = begin
  if Rails.env.test?
    nil
  else
    Aws::S3::Client.new
  end
rescue StandardError
  nil
end
