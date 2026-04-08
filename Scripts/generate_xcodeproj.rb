require "fileutils"
require "xcodeproj"

PROJECT_NAME = "ScanovaApp".freeze
PROJECT_PATH = File.expand_path("../#{PROJECT_NAME}.xcodeproj", __dir__)
ROOT_PATH = File.expand_path("..", __dir__)

SOURCE_DIRECTORIES = %w[
  App
  Core
  Features
  Components
].freeze

RESOURCE_FILES = %w[
  PrivacyInfo.xcprivacy
].freeze

def sorted_entries(path)
  Dir.children(path).sort
end

def add_directory(group, absolute_path, target)
  sorted_entries(absolute_path).each do |entry|
    next if entry.start_with?(".")

    full_path = File.join(absolute_path, entry)
    extension = File.extname(entry)

    if File.directory?(full_path) && extension == ".xcassets"
      file_reference = group.find_file_by_path(entry) || group.new_file(full_path)
      target.resources_build_phase.add_file_reference(file_reference, true)
      next
    end

    if File.directory?(full_path)
      subgroup = group.find_subpath(entry, true)
      add_directory(subgroup, full_path, target)
      next
    end

    file_reference = group.find_file_by_path(entry) || group.new_file(full_path)

    case extension
    when ".swift"
      target.add_file_references([file_reference])
    when ".xcassets"
      target.resources_build_phase.add_file_reference(file_reference, true)
    end
  end
end

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2600"
project.root_object.attributes["LastUpgradeCheck"] = "2600"

main_group = project.main_group

source_root_groups = {}
SOURCE_DIRECTORIES.each do |directory|
  source_root_groups[directory] = main_group.find_subpath(directory, true)
end

products_group = main_group.find_subpath("Products", true)

target = project.new_target(:application, PROJECT_NAME, :ios, "17.0")
target.product_reference.name = "#{PROJECT_NAME}.app"

target.build_configurations.each do |config|
  config.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.salonikhobragade.scanova"
  config.build_settings["MARKETING_VERSION"] = "1.0.0"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
  config.build_settings["SWIFT_VERSION"] = "5.0"
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  config.build_settings["TARGETED_DEVICE_FAMILY"] = "1,2"
  config.build_settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
  config.build_settings["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents"] = "YES"
  config.build_settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_CFBundleDisplayName"] = "Scanova"
  config.build_settings["INFOPLIST_KEY_NSCameraUsageDescription"] = "Scan paper documents and convert them into PDFs."
  config.build_settings["INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription"] = "Save exported document pages as images to your Photos library."
  config.build_settings["INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone"] = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
  config.build_settings["INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad"] = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["DEVELOPMENT_TEAM"] = "6Z7AHUWB5H"

  if config.name == "Release"
    config.build_settings["CODE_SIGN_IDENTITY"] = "Apple Distribution"
  else
    config.build_settings["CODE_SIGN_IDENTITY"] = "Apple Development"
  end
end

debug_config = target.build_configuration_list["Debug"]
debug_config.build_settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"

SOURCE_DIRECTORIES.each do |directory|
  add_directory(source_root_groups.fetch(directory), File.join(ROOT_PATH, directory), target)
end

RESOURCE_FILES.each do |resource_path|
  absolute_path = File.join(ROOT_PATH, resource_path)
  next unless File.exist?(absolute_path)

  file_reference = main_group.find_file_by_path(resource_path) || main_group.new_file(absolute_path)
  target.resources_build_phase.add_file_reference(file_reference, true)
end

project.save
