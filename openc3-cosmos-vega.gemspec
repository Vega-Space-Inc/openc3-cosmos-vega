# encoding: ascii-8bit

# Create the overall gemspec
Gem::Specification.new do |s|
  s.name = 'openc3-cosmos-vega'
  s.summary = 'Adjacent Satellite Interference Risk for COSMOS, powered by Vega'
  s.description = <<-EOF
    Adjacent satellite interference (ASI) risk for your satellites and ground
    stations: a pass-by-band timeline widget of forecast and measured
    interference, plus COSMOS telemetry of the organization's satellites,
    ground stations and forecast status. Forecasts and history come from the
    Vega API (vega.space).
  EOF
  # Custom license (text in LICENSE.md). RubyGems warns that this is not an SPDX id;
  # the reference OpenC3 plugins carry the same warning with 'OpenC3'. The store shows the string.
  s.licenses = 'Vega Plugin License'
  s.authors = ['Vega Space, Inc.']
  s.email = ['tom@vega.space']
  s.homepage = 'https://vega.space'
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 3.0'

  if ENV['VERSION']
    s.version = ENV['VERSION'].dup
  else
    time = Time.now.strftime("%Y%m%d%H%M%S")
    s.version = '0.0.0' + ".#{time}"
  end
  s.files = Dir.glob("{targets,lib,public,tools,microservices}/**/*") + %w(Rakefile README.md LICENSE.md THIRD_PARTY_LICENSES.md plugin.txt) # the widget .map must ship: WidgetModel copies it at install

  s.metadata = {
    # These fields are used when you submit your plugin to the OpenC3 Store at store.openc3.com
    # See this help page for more detail: https://store.openc3.com/help/guidelines
    "source_code_uri" => "https://github.com/Vega-Space-Inc/openc3-cosmos-vega",
    "openc3_store_title" => "Adjacent Satellite Interference Risk",
    "openc3_store_description" => "Forecast and measured adjacent-satellite interference risk for your satellites and ground stations, as a pass-by-band timeline widget and COSMOS telemetry. Powered by Vega.",
    "openc3_store_keywords" => "asi, interference, satellite, spectrum, rf, coverage, vega",
    "openc3_store_image" => "public/store_img.png",
    "openc3_cosmos_minimum_version" => "7.3.0", # the @openc3/js-common used by the widget is 7.3.0; built and run against 7.3.1
    "openc3_store_access_type" => "public" # OPTIONAL
  }
end
