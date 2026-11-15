# frozen_string_literal: true

module Riffer::Rig::Mcp
  Server = Data.define(
    :declaration, #: Riffer::Rig::Mcp::Declaration
    :registration #: Riffer::Mcp::Registration
  )
end
