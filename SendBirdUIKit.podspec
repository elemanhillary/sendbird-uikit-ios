Pod::Spec.new do |s|
	s.name         = "SendBirdUIKit"
	s.version      = "2.1.11"
	s.summary      = "UIKit based on SendBirdSDK"
	s.description  = "SendBird UIKit is a framework composed of basic UI components based on SendBirdSDK."
	s.homepage     = "https://sendbird.com"
	s.documentation_url = 'https://docs.sendbird.com/ios'
	s.license      = "Commercial"
	s.authors      = {
	"Jaesung Lee" => "jaesung.lee@sendbird.com",
	"Jed Gyeong" => "jed.gyeong@sendbird.com", 
	"Woo" => "wooyoung.chung@sendbird.com",
	"Tez" => "tez.park@sendbird.com"
  	}
	s.platform     = :ios, "10.3"
	s.source = { :git => "https://github.com/sendbird/sendbird-uikit-ios.git", :tag => "v#{s.version}" }
	s.ios.vendored_frameworks = 'SendBirdUIKit.xcframework'
	s.ios.frameworks = ["UIKit", "Foundation", "CoreData", "SendBirdSDK"]
	s.requires_arc = true
	s.dependency "SendBirdSDK", "~>3.0.226"
	s.ios.library = "icucore"
	s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
	s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
end
