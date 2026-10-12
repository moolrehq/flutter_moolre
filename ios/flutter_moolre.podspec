Pod::Spec.new do |s|
  s.name             = 'flutter_moolre'
  s.version          = '0.1.0'
  s.summary          = 'Moolre checkout for Flutter.'
  s.description      = <<-DESC
In-app browser for Moolre's hosted payment page, built on WKWebView.
                       DESC
  s.homepage         = 'https://moolre.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Moolre' => 'support@moolre.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks       = 'WebKit'
  s.platform         = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'flutter_moolre_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
