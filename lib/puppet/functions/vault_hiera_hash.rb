# @summary Custom hiera back-end for Hashicorp Vault key/value secrets engine
#
Puppet::Functions.create_function(:vault_hiera_hash) do
  # @param options Hash containing:
  # @option uri        Required. The complete URI to the API endpoint of a Vault key/value secrets path.
  # @option token_file Optional. Path to a file that contains a Vault token, otherwise will try PKI auth with Puppet cert
  # @option auth_path  Optional. The Vault path for the "cert" authentication type used with Puppet certificates
  # @option version    Optional. Defaults to Vault key/value secrets engine v1 unless this is set to 'v2'.
  # @option timeout    Optional. Default is 5 seconds.
  # @option ca_trust   Required. The path to trusted CA certificate chain file.
  # @param context     Default parameter used for caching
  # @return [Hash] All key/value pairs from the given Vault path will be returned to hiera
  dispatch :vault_hiera_hash do
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  require "#{File.dirname(__FILE__)}/../shared/vault_common.rb"

  def vault_hiera_hash(options, context)
    err_message = "The vault_hiera_hash function requires one of 'uri' or 'uris'"
    raise Puppet::DataBinding::LookupError, err_message unless options.key?('uri')

    Puppet.debug "Using Vault uri: #{options['uri']}"

    err_message = "The vault_hiera_hash function requires the 'ca_trust' parameter"
    raise Puppet::DataBinding::LookupError, err_message unless options.key?('ca_trust')

    err_message = "The 'ca_trust' file was not found: #{options['ca_trust']}"
    raise Puppet::DataBinding::LookupError, err_message unless File.file?(options['ca_trust'])

    err_message = "The vault_hiera_hash 'token_file' does not exist: #{options['token_file']}"
    raise Puppet::DataBinding::LookupError, err_message if options.key?('token_file') && !File.file?(options['token_file'])

    err_message = "The vault_hiera_hash options require either 'token_file' or 'auth_path'"
    raise Puppet::DataBinding::LookupError, err_message unless options.key?('token_file') || options.key?('auth_path')

    uri = URI(options['uri'])
    err_message = "Function vault_hiera_hash failed parse a hostname from #{options['uri']}"
    raise Puppet::DataBinding::LookupError, err_message unless uri.hostname

    timeout = if options.key?('timeout')
                options[:timeout]
              else
                5
              end

    http = http_create_secure(uri, options['ca_trust'], timeout)

    # Read token from file or authenticate with the Puppet certificate
    token = if options.key?('token_file')
              File.read(options['token_file']).strip
            else
              vault_get_token(http, options['auth_path'].delete('/'))
            end

    secrets = vault_http_get(http, uri.path, token)
    data = if options['version'] == 'v2'
             vault_parse_data(secrets, 'v2')
           else
             vault_parse_data(secrets, 'v1')
           end
    context.not_found if data.empty? || !data.is_a?(Hash)
    context.cache_all(data)
    data
  end
end
