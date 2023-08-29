class OriginValidator
  attr_accessor :app, :host

  def initialize(app:, host:)
    @app = app
    @host = host
  end

  class NonAcceptedOrigin < StandardError
    def message
      "not accepted origin, check your app's domain_url or the origin were your widget is installed"
    end
  end

  def is_valid?
    return true if @app.blank?
    return true if @app == "*"

    raise NonAcceptedOrigin if @app.delete(" ").split(",").map do |domain|
      validate_domain(domain)
    end.none?  do |r|
      r == true
    end

    true
  end

  def validate_domain(domain)
    env_domain = Addressable::URI.parse(
      host
    )

    env_domain_without_subdomain = Addressable::URI.parse(without_subdomain(env_domain))

    app_domain = Addressable::URI.parse(domain)

    # for now we will check for domain
    if app_domain.normalized_site != env_domain.normalized_site ||
      app_domain.normalized_site != env_domain_without_subdomain.normalized_site
      return false
    end

    true
  end

  def without_subdomain(env_domain)
    subdomains = env_domain.host.split('.')
    subdomains.shift
    modified_url = "#{env_domain.scheme}://#{subdomains.join('.')}#{env_domain.path}"

    modified_url
  end
end
