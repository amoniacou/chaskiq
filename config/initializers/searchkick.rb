if Chaskiq::Config.get("SEARCHKICK_ENABLED").present?
  Searchkick.client_type = Chaskiq::Config.fetch("SEARCHKICK_CLIENT", "elasticsearch").to_sym
end
