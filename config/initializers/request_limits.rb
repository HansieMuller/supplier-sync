require Rails.root.join("lib/request_size_limit")
Rails.application.config.middleware.insert_before 0, RequestSizeLimit
