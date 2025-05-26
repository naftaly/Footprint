Pod::Spec.new do |spec|
  spec.name         = "Footprint"
  spec.version      = "1.0.6"
  spec.summary      = "Footprint is a Swift library that facilitates dynamic memory management."
  spec.description  = "Footprint is a Swift library that facilitates dynamic memory management in iOS apps"
  spec.homepage     = "https://github.com/naftaly/Footprint"
  spec.license      = "MIT"
  spec.author             = { "Alex Cohen" => "naftaly@me.com" }
  spec.ios.deployment_target = "13.0"
  spec.osx.deployment_target = "10.15"
  spec.watchos.deployment_target = "6.0"
  spec.tvos.deployment_target = "13.0"
  spec.visionos.deployment_target = "1.0"
  spec.source       = { :git => "https://github.com/naftaly/Footprint.git", :tag => "v#{spec.version}" }
  spec.source_files  = "Sources", "Sources/**/*.{h,m,swift}"
  spec.swift_versions = "5.0"
end
