module DomoscioRails
  # A RuleInput.
  class RuleInput < Resource
    include DomoscioRails::HTTPCalls::Create
    include DomoscioRails::HTTPCalls::Fetch
    include DomoscioRails::HTTPCalls::Update
    include DomoscioRails::HTTPCalls::Destroy
  end
end