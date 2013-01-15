Pod::Spec.new do |s|
  s.name         = "taskit"
  s.version      = "0.0.1"
  s.license      = 'WTFPL'
  s.summary      = "NSTask reimplementation a simpler interface"
  s.author       = { "Alex Gordon" => "alextgordon@gmail.com" }
  s.homepage     = 'https://github.com/fileability/taskit'
  s.source       = { :git => "git://github.com/fileability/taskit.git", :commit => "96eaa8ef0f66dc98b02d9686d6f3e38bb5981b99" }
  s.source_files = '*.{h,m}'
end
