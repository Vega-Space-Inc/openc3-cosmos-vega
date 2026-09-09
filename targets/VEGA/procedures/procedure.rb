# Script Runner test script - confirms the Vega frontend API key is valid and
# the interface is reachable. Run this after installing/reconfiguring the plugin.
cmd("VEGA GET_APPROVED_ORGS")
wait_check("VEGA APPROVED_ORGS HTTP_STATUS == 200", 10)
puts "Vega API key OK, first approved org: #{tlm('VEGA APPROVED_ORGS FIRST_ORG_NAME')} (id #{tlm('VEGA APPROVED_ORGS FIRST_ORG_ID')})"
