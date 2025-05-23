GLOBAL_DATUM_INIT(keycard_events, /datum/events, new)

#define KEYCARD_RED_ALERT "Red Alert"
#define KEYCARD_EMERGENCY_MAINTENANCE_ACCESS "Emergency Maintenance Access"
#define KEYCARD_BSA_UNLOCK "Bluespace Artillery Unlock"
//NSV13
#define KEYCARD_FTL_SAFETY_OVERRIDE "FTL Safety Override"
//NSV13 end.

/obj/machinery/keycard_auth
	name = "Keycard Authentication Device"
	desc = "This device is used to trigger station functions, which require more than one ID card to authenticate."
	icon = 'icons/obj/monitors.dmi'
	icon_state = "auth_off"
	use_power = IDLE_POWER_USE
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = AREA_USAGE_ENVIRON
	req_access = list(ACCESS_KEYCARD_AUTH)
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	layer = ABOVE_WINDOW_LAYER



	var/datum/callback/ev
	var/event = ""
	var/obj/machinery/keycard_auth/event_source
	///Triggering ID card relayed to auth devices to make sure two keycards are used.
	var/obj/item/card/id/triggering_card
	var/mob/triggerer = null
	var/waiting = 0

/obj/machinery/keycard_auth/Initialize(mapload)
	. = ..()
	ev = GLOB.keycard_events.addEvent("triggerEvent", CALLBACK(src, PROC_REF(triggerEvent)))

/obj/machinery/keycard_auth/Destroy()
	GLOB.keycard_events.clearEvent("triggerEvent", ev)
	QDEL_NULL(ev)
	return ..()


/obj/machinery/keycard_auth/ui_state(mob/user)
	return GLOB.physical_state

/obj/machinery/keycard_auth/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "KeycardAuth")
		ui.open()
		ui.set_autoupdate(TRUE)

/obj/machinery/keycard_auth/ui_data()
	var/list/data = list()
	data["waiting"] = waiting
	data["auth_required"] = event_source ? event_source.event : 0
	data["red_alert"] = (seclevel2num(get_security_level()) >= SEC_LEVEL_RED) ? 1 : 0
	data["emergency_maint"] = GLOB.emergency_access
	data["bsa_unlock"] = GLOB.bsa_unlock
	//NSV13 - emergency FTL
	var/ftl_state = -1 // -1 = not overmap; 0 = Safe; 1 = Unsafe.
	var/obj/structure/overmap/current_overmap = get_overmap()
	if(current_overmap)
		ftl_state = current_overmap.ftl_safety_override
	data["ftl_safety_override"] = ftl_state
	//NSV13 end
	return data

/obj/machinery/keycard_auth/ui_status(mob/user)
	if(isanimal(user))
		var/mob/living/simple_animal/A = user
		if(!A.dextrous)
			to_chat(user, "<span class='warning'>You are too primitive to use this device!</span>")
			return UI_CLOSE
	return ..()

/obj/machinery/keycard_auth/ui_act(action, params)
	if(..() || waiting || !allowed(usr))
		return
	var/obj/item/card/swipe_id = usr.get_idcard()
	if(!swipe_id || !istype(swipe_id))
		to_chat(usr, "<span class='warning'>No ID card detected.</span>")
		return
	switch(action)
		if("red_alert")
			if(!event_source)
				//NSV13 - delta alert level override.
				if(GLOB.security_level == SEC_LEVEL_DELTA)
					to_chat(usr, "<span class='warning'>Security level override active.</span>")
					return
				//NSV13 end.
				sendEvent(KEYCARD_RED_ALERT, swipe_id)
				. = TRUE
		if("emergency_maint")
			if(!event_source)
				sendEvent(KEYCARD_EMERGENCY_MAINTENANCE_ACCESS, swipe_id)
				. = TRUE
		if("auth_swipe")
			if(event_source)
				//NSV13 - cross overmap safety even if the other things don't have it (we can have a subtype for syndi vessels that doesn't have the other options?).
				var/overmap1 = event_source.get_overmap()
				var/overmap2 = get_overmap()
				if(overmap1 != overmap2)
					return TRUE
				//NSV13 end.
				if(swipe_id == event_source.triggering_card)
					to_chat(usr, "<span class='warning'>Invalid ID. Confirmation ID must not equal trigger ID.</span>")
					return
				event_source.trigger_event(usr)
				event_source = null
				. = TRUE
		if("bsa_unlock")
			if(!event_source)
				sendEvent(KEYCARD_BSA_UNLOCK, swipe_id)
				. = TRUE
		if("ftl_safety_override")
			if(!event_source)
				sendEvent(KEYCARD_FTL_SAFETY_OVERRIDE, swipe_id)
				. = TRUE


/obj/machinery/keycard_auth/proc/sendEvent(event_type, obj/item/card/id/swipe_id)
	triggerer = usr
	triggering_card = swipe_id //Shouldn't need qdel registering due to very short time before this var resets.
	event = event_type
	waiting = 1
	GLOB.keycard_events.fireEvent("triggerEvent", src)
	addtimer(CALLBACK(src, PROC_REF(eventSent)), 20)

/obj/machinery/keycard_auth/proc/eventSent()
	triggerer = null
	triggering_card = null
	event = ""
	waiting = 0

/obj/machinery/keycard_auth/proc/triggerEvent(source)
	icon_state = "auth_on"
	event_source = source
	addtimer(CALLBACK(src, PROC_REF(eventTriggered)), 20)

/obj/machinery/keycard_auth/proc/eventTriggered()
	icon_state = "auth_off"
	event_source = null

/obj/machinery/keycard_auth/proc/trigger_event(confirmer)
	//NSV13 - delta alert overrides security level change sources.
	if(event == KEYCARD_RED_ALERT && GLOB.security_level == SEC_LEVEL_DELTA)
		to_chat(confirmer, "<span class='warning'>Security level override active.</span>")
		return
	//NSV13 end.
	log_game("[key_name(triggerer)] triggered and [key_name(confirmer)] confirmed event [event]")
	message_admins("[ADMIN_LOOKUPFLW(triggerer)] triggered and [ADMIN_LOOKUPFLW(confirmer)] confirmed event [event]")

	var/area/A1 = get_area(triggerer)
	deadchat_broadcast("<span class='deadsay'><span class='name'>[triggerer]</span> triggered [event] at <span class='name'>[A1.name]</span>.</span>", triggerer)

	var/area/A2 = get_area(confirmer)
	deadchat_broadcast("<span class='deadsay'><span class='name'>[confirmer]</span> confirmed [event] at <span class='name'>[A2.name]</span>.</span>", confirmer)
	switch(event)
		if(KEYCARD_RED_ALERT)
			set_security_level(SEC_LEVEL_RED)
		if(KEYCARD_EMERGENCY_MAINTENANCE_ACCESS)
			make_maint_all_access()
		if(KEYCARD_BSA_UNLOCK)
			toggle_bluespace_artillery()
		if(KEYCARD_FTL_SAFETY_OVERRIDE)
			toggle_ftl_drive_safety(get_overmap())

GLOBAL_VAR_INIT(emergency_access, FALSE)
/proc/make_maint_all_access()
	for(var/area/maintenance/M as() in get_areas(/area/maintenance, SSmapping.levels_by_trait(ZTRAIT_STATION)[1]))
		for(var/obj/machinery/door/airlock/A in M)
			A.emergency = TRUE
			A.update_icon()
			A.wires.ui_update()
	minor_announce("Access restrictions on maintenance and external airlocks have been lifted.", "Attention! Station-wide emergency declared!",1)
	GLOB.emergency_access = TRUE
	SSblackbox.record_feedback("nested tally", "keycard_auths", 1, list("emergency maintenance access", "enabled"))

/proc/revoke_maint_all_access()
	for(var/area/maintenance/M as() in get_areas(/area/maintenance, SSmapping.levels_by_trait(ZTRAIT_STATION)[1]))
		for(var/obj/machinery/door/airlock/A in M)
			A.emergency = FALSE
			A.update_icon()
			A.wires.ui_update()
	minor_announce("Access restrictions in maintenance areas have been restored.", "Attention! Station-wide emergency rescinded:")
	GLOB.emergency_access = FALSE
	SSblackbox.record_feedback("nested tally", "keycard_auths", 1, list("emergency maintenance access", "disabled"))

/proc/toggle_bluespace_artillery()
	GLOB.bsa_unlock = !GLOB.bsa_unlock
	minor_announce("Bluespace Artillery firing protocols have been [GLOB.bsa_unlock? "unlocked" : "locked"]", "Weapons Systems Update:")
	SSblackbox.record_feedback("nested tally", "keycard_auths", 1, list("bluespace artillery", GLOB.bsa_unlock? "unlocked" : "locked"))

///NSV13 - toggles FTL safety mode of a passed vessel.
/proc/toggle_ftl_drive_safety(obj/structure/overmap/target)
	if(QDELETED(target))
		return
	target.ftl_safety_override = !target.ftl_safety_override
	if(target.ftl_safety_override) //Safety disengaged.
		target.relay('nsv13/sound/misc/triple_boop_alert.ogg',"<h1 class='alert'>FTL Drive System Notice</h1><span class='alert'>FTL Drive Safeties disengaged. Drive reverting to manual control.</span><br>")
	else //Safety reengaged.
		target.relay('sound/misc/notice2.ogg', "<h1 class='alert'>FTL Drive System Notice</h1><span class='alert'>FTL Drive Safeties restored.</span><br>")
//NSV13 end.

#undef KEYCARD_RED_ALERT
#undef KEYCARD_EMERGENCY_MAINTENANCE_ACCESS
#undef KEYCARD_BSA_UNLOCK
#undef KEYCARD_FTL_SAFETY_OVERRIDE
