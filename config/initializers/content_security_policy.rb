Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.style_src :self
    policy.img_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end
end
