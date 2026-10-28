#!/usr/bin/env ruby
# Adds the test targets to Trop.xcodeproj — only in CI (test workflow), the
# committed project stays untouched so the release build is unaffected.
#
#   ResonaTests    unit tests, hosted in Trop.app (@testable import Trop)
#   ResonaUITests  XCUITest tour (screenshots)
#   scheme "ResonaTests" builds the app and runs both.
#
# Sources: Tests/ResonaTests/*.swift (+ Fixtures/*.json as resources) and
# Tests/ResonaUITests/*.swift.

require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'Trop.xcodeproj'))
app = project.targets.find { |t| t.name == 'Trop' } or abort('Trop target missing')

if project.targets.any? { |t| t.name == 'ResonaTests' }
  puts 'Test targets already present.'
  exit 0
end

tests_group = project.main_group.find_subpath('Tests', true)
tests_group.set_source_tree('<group>')
tests_group.set_path('Tests')

def add_target(project, app, group, name, type, sources_dir)
  target = project.new_target(type, name, :ios, '18.0', nil, :swift)
  sub = group.find_subpath(name, true)
  sub.set_source_tree('<group>')
  sub.set_path(name)
  Dir[File.join(sources_dir, '*.swift')].sort.each do |file|
    target.add_file_references([sub.new_reference(File.basename(file))])
  end
  fixtures = File.join(sources_dir, 'Fixtures')
  if Dir.exist?(fixtures)
    fixtures_group = sub.find_subpath('Fixtures', true)
    fixtures_group.set_source_tree('<group>')
    fixtures_group.set_path('Fixtures')
    Dir[File.join(fixtures, '*.json')].sort.each do |file|
      target.resources_build_phase.add_file_reference(fixtures_group.new_reference(File.basename(file)))
    end
  end
  target.add_dependency(app)
  target.build_configurations.each do |config|
    s = config.build_settings
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "dev.jackderganove.resona.#{name.downcase}"
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['SWIFT_VERSION'] = '5.0'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['SWIFT_ENABLE_EXPLICIT_MODULES'] = 'NO'
    s['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  end
  target
end

unit = add_target(project, app, tests_group, 'ResonaTests', :unit_test_bundle, File.join(root, 'Tests/ResonaTests'))
unit.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Trop.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Trop'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end

ui = add_target(project, app, tests_group, 'ResonaUITests', :ui_test_bundle, File.join(root, 'Tests/ResonaUITests'))
ui.build_configurations.each do |config|
  config.build_settings['TEST_TARGET_NAME'] = 'Trop'
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(unit)
scheme.add_test_target(ui)
scheme.set_launch_target(app)
scheme.test_action.build_configuration = 'Debug'
scheme.launch_action.build_configuration = 'Debug'
scheme.save_as(project.path, 'ResonaTests', true)

puts "Added ResonaTests (#{unit.source_build_phase.files.count} files, #{unit.resources_build_phase.files.count} fixtures) " \
     "and ResonaUITests (#{ui.source_build_phase.files.count} files), scheme ResonaTests."
