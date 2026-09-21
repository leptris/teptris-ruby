source "https://rubygems.org"

gemspec

group :development, :test do
  gem "rake"
  gem "rspec"
  gem "tomlib" # parity reference in specs; optional at runtime
  gem "tomlrb" # benchmark tier reference
  gem "racc" # tomlrb's parser needs it but does not declare it (ruby 3.3 dropped the default gem)
end
