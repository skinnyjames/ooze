

class RubyResolver
  def self.write_to_file(path, filename)
    code = new(path).code
    File.open(filename, "w") do |io|
      io << code
    end
  end

  def initialize(file_path, document = File.read(file_path))
    @file_path = file_path
    @document = document
  end

  def code
    resolve_imports!

    @document
  end

  def resolve_imports!
    file_path_dir = File.dirname(@file_path)

    @document = @document.gsub(/(?:require_relative\s+["'](.*)["'])/) do |path|
      base_path = Pathname.new(@file_path)
      path = Pathname.new("#{path.gsub(/require_relative\s+["']/, "").chop}.rb")
      resolved_path = Pathname.join(File.dirname(base_path.to_s), path).to_s

      RubyResolver.new(resolved_path).code
    end
  end
end

def ruby_file(file)
  RubyResolver.new(file).code
end