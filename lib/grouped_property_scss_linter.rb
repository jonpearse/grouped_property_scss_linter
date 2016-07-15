require "grouped_property_scss_linter/version"
require "grouped_property_scss_linter/grouped_property_order"
require "ext/string"

module GroupedPropertyScssLinter

  STYLES_DIR = File.realpath(File.join(File.dirname(__FILE__), '..', 'data')).freeze

end
