require 'fileutils'

public_dir = File.join(File.dirname(__FILE__),'/../../../public')
asset_dir = File.join(File.dirname(__FILE__), 'assets')

['images','stylesheets','javascripts'].each do |asset_type|
  current_dir = File.join(asset_dir, asset_type)
  Dir.entries(current_dir).each do |f|
    path = File.join(public_dir,asset_type,f)
    FileUtils.cp(File.join(asset_dir,asset_type,f), path) unless File.exist?(path) || File.directory?(path)
  end
end
puts IO.read(File.join(File.dirname(__FILE__), 'README'))