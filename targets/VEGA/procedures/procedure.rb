# Smoke test for the Vega plugin - run from Script Runner after installing or
# reconfiguring it. Two parts:
#
#   1. Live: sends GET_APPROVED_ORGS and confirms the VEGA_API_KEY secret is
#      accepted (HTTP 200), printing the first approved organization.
#   2. Offline: injects FORECASTING_SUMMARY values to walk RUN_STALE through
#      its OK / STALE states and HTTP_STATUS through 200 / 500 so the status
#      screen can be watched without waiting on real data, then refetches the
#      real packet to put things back.
#
# No packet declares LIMITS (see README), so HTTP_STATUS carries no colour;
# RUN_STALE is a STATE item and its state name shows on the screen.

TARGET = 'VEGA' # match vega_target_name if the plugin was installed under another name
PACKET = 'FORECASTING_SUMMARY'
STAGE_WAIT = 5 # Seconds to hold each stage so the status screen can be watched

# ---------- 1. Live: is the API key secret valid? ----------
# Compare RECEIVED_COUNT so a 200 left over from an earlier poll can't pass
# the check for a command that actually failed.
before = tlm("#{TARGET} APPROVED_ORGS RECEIVED_COUNT")
cmd("#{TARGET} GET_APPROVED_ORGS")
begin
  wait_check("#{TARGET} APPROVED_ORGS RECEIVED_COUNT > #{before}", 15)
  check("#{TARGET} APPROVED_ORGS HTTP_STATUS == 200")
  puts "Vega API key OK - first approved org: #{tlm("#{TARGET} APPROVED_ORGS FIRST_ORG_NAME")} (id #{tlm("#{TARGET} APPROVED_ORGS FIRST_ORG_ID")})"
rescue CheckError => e
  status = tlm("#{TARGET} ERROR_RESPONSE HTTP_STATUS")
  case status
  when 401
    puts "GET_APPROVED_ORGS returned 401: the VEGA_API_KEY secret is missing or invalid."
    puts "This script uses the shared-secret path. Users normally enter their own key in the Timeline widget; to fix this path, create the secret in Admin / Secrets (name VEGA_API_KEY, value = a vgk_... key from the Vega app) and restart #{TARGET}_INT."
  when nil
    puts "No response within 15 s - is #{TARGET}_INT connected? (#{e.message})"
  else
    puts "GET_APPROVED_ORGS failed with HTTP #{status}: #{tlm("#{TARGET} ERROR_RESPONSE BODY").to_s[0, 200]}"
  end
end

# ---------- 2. Offline: walk the status-screen alerts ----------
# get_tlm_values returns [value, limits_state] per item. For a STATE coloured
# item the limits_state is the state's colour.
def report_alerts
  stale, http = get_tlm_values(["#{TARGET}__#{PACKET}__RUN_STALE__CONVERTED",
                                "#{TARGET}__#{PACKET}__HTTP_STATUS__CONVERTED"])
  puts "  RUN_STALE = #{stale[0]} (#{stale[1]}), HTTP_STATUS = #{http[0]} (#{http[1]})"
end

# name, RUN_STALE state, HTTP_STATUS
STAGES = [
  ['Nominal',                            'OK',    200],
  ['Stale forecast run - RUN_STALE = STALE', 'STALE', 200],
  ['API failure - HTTP_STATUS 500',      'STALE', 500],
  ['Back to nominal',                    'OK',    200],
]

STAGES.each do |name, stale, status|
  inject_tlm(TARGET, PACKET, { 'RUN_STALE' => stale, 'HTTP_STATUS' => status })
  puts name
  wait(2) # Let decom update the CVT before reading it back
  report_alerts()
  wait(STAGE_WAIT)
end

# Restore: refetch the real packet (needs vega_org_id set; with it at 0 the
# request 404s into ERROR_RESPONSE and the injected values simply stay until
# the next real poll).
cmd("#{TARGET} GET_FORECASTING_SUMMARY")
puts "Done. Sent #{TARGET} GET_FORECASTING_SUMMARY to restore real values."
