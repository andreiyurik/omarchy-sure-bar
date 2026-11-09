# Creates a test family with one account and two API keys, then prints the keys.
family = Family.create!(name: "VPS test", currency: "USD", locale: "en", country: "US", timezone: "UTC", date_format: "%Y-%m-%d")
user = family.users.create!(email: "vps@example.test", password: "Vps-Test-Pass-12345!", first_name: "Vps", last_name: "Test",
  role: "admin", onboarded_at: Time.current)
family.accounts.create!(name: "Cash", balance: 1000, currency: "USD", accountable: Depository.new, status: "active")
[ [ "rw", [ "read_write" ] ], [ "ro", [ "read" ] ] ].each do |name, scopes|
  key = ApiKey.generate_secure_key
  user.api_keys.create!(name: name, scopes: scopes, display_key: key, source: "web")
  puts "KEY #{name} #{key}"
end
