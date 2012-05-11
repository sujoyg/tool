require "erb"
require "yaml"

module Tool
  class Constant
    def initialize(constants={})
      @constants = constants
    end

    def self.read(constants_file)
      Constant.new ::YAML.load(::ERB.new(File.read constants_file).result)
    end

    def method_missing(method_name, *method_args)
      if @constants.key?(method_name.to_s)
        value = @constants[method_name.to_s]
        value.is_a?(Hash) ? Constant.new(value) : value
      else # We want to raise NoMethodError
        nil
      end
    end

    def [](key)
      value = @constants[key.to_s]
      value.is_a?(Hash) ? Constant.new(value) : value
    end
  end
end
