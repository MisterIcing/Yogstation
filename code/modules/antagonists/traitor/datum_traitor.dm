#define TRAITOR_HUMAN "human"
#define TRAITOR_AI	  "AI"

/datum/antagonist/traitor
	name = "Traitor"
	roundend_category = "traitors"
	antagpanel_category = "Traitor"
	job_rank = ROLE_TRAITOR
	antag_hud_name = "traitor"
	antag_moodlet = /datum/mood_event/focused
	preview_outfit = /datum/outfit/traitor
	count_towards_antag_cap = TRUE
	var/special_role = ROLE_TRAITOR
	var/employer = "The Syndicate"
	var/give_objectives = TRUE
	var/should_give_codewords = TRUE
	var/should_equip = TRUE
	var/traitor_kind = TRAITOR_HUMAN //Set on initial assignment
	var/malf = FALSE //whether or not the AI is malf (in case it's a traitor)
	var/datum/contractor_hub/contractor_hub
	var/obj/item/uplink_holder
	can_hijack = HIJACK_HIJACKER
	/// If this specific traitor has been assigned codewords. This is not always true, because it varies by faction.
	var/has_codewords = FALSE
	var/datum/weakref/uplink_ref

/datum/antagonist/traitor/on_gain()
	if(owner.current && iscyborg(owner.current))
		var/mob/living/silicon/robot/robot = owner.current
		if(robot.shell)
			robot.undeploy()

	if(owner.current && isAI(owner.current))
		traitor_kind = TRAITOR_AI

	if(traitor_kind == TRAITOR_AI)
		company = /datum/corporation/self
	else if(!company)
		company = pick(subtypesof(/datum/corporation/traitor))
	owner.add_employee(company)

	SSgamemode.traitors += owner
	owner.special_role = special_role
	if(give_objectives)
		forge_traitor_objectives()
	finalize_traitor()
	RegisterSignal(owner.current, COMSIG_MOVABLE_HEAR, PROC_REF(handle_hearing))
	..()


/datum/antagonist/traitor/apply_innate_effects(mob/living/mob_override)
	. = ..()
	var/mob/living/silicon/ai/A = mob_override || owner.current
	if(istype(A) && traitor_kind == TRAITOR_AI)
		A.hack_software = TRUE
	handle_clown_mutation(owner.current, "Your training has allowed you to overcome your clownish nature, allowing you to wield weapons without harming yourself.")

/datum/antagonist/traitor/remove_innate_effects(mob/living/mob_override)
	. = ..()
	var/mob/living/silicon/ai/A = mob_override || owner.current
	if(istype(A)  && traitor_kind == TRAITOR_AI)
		A.hack_software = FALSE

/datum/antagonist/traitor/on_removal()
	//Remove malf powers.
	if(traitor_kind == TRAITOR_AI && owner.current && isAI(owner.current))
		var/mob/living/silicon/ai/A = owner.current
		A.set_zeroth_law("")
		for(var/datum/action/innate/ai/ranged/cameragun/ai_action in A.actions)
			if(ai_action.from_traitor)
				ai_action.Remove(A)
		if(malf)
			remove_verb(A, /mob/living/silicon/ai/proc/choose_modules)
			A.malf_picker.remove_malf_verbs(A)
			qdel(A.malf_picker)
	owner.remove_employee(company)
	if(uplink_holder)
		var/datum/component/uplink/uplink = uplink_holder.GetComponent(/datum/component/uplink)
		if(uplink)//remove uplink so they can't keep using it if admin abuse happens
			qdel(uplink)
	UnregisterSignal(owner.current, COMSIG_MOVABLE_HEAR)
	SSgamemode.traitors -= owner
	if(!silent && owner.current)
		to_chat(owner.current,span_userdanger(" You are no longer the [special_role]! "))
	owner.special_role = null
	..()

/datum/antagonist/traitor/proc/handle_hearing(datum/source, list/hearing_args)
	var/message = hearing_args[HEARING_MESSAGE]
	message = GLOB.syndicate_code_phrase_regex.Replace(message, span_blue("$1"))
	message = GLOB.syndicate_code_response_regex.Replace(message, span_red("$1"))
	hearing_args[HEARING_MESSAGE] = message

/datum/antagonist/traitor/proc/add_objective(datum/objective/O)
	objectives += O

/datum/antagonist/traitor/proc/remove_objective(datum/objective/O)
	objectives -= O

/datum/antagonist/traitor/proc/forge_traitor_objectives()
	switch(traitor_kind)
		if(TRAITOR_AI)
			forge_ai_objectives()
		else
			forge_human_objectives()

/datum/antagonist/traitor/proc/forge_human_objectives()
	var/is_hijacker = FALSE
	if (GLOB.joined_player_list.len >= 30) // Less murderboning on lowpop thanks
		is_hijacker = prob(10)
	var/martyr_chance = prob(20)
	var/objective_count = is_hijacker 			//Hijacking counts towards number of objectives
	if(!SSgamemode.exchange_blue && SSgamemode.traitors.len >= 6) 	//Set up an exchange if there are enough traitors. YOGSTATION CHANGE: 8 TO 6.
		if(!SSgamemode.exchange_red)
			SSgamemode.exchange_red = owner
		else
			SSgamemode.exchange_blue = owner
			assign_exchange_role(SSgamemode.exchange_red)
			assign_exchange_role(SSgamemode.exchange_blue)
		objective_count += 1					//Exchange counts towards number of objectives
	var/toa = CONFIG_GET(number/traitor_objectives_amount)
	for(var/i = objective_count, i < toa, i++)
		forge_single_human_objective()

	forge_single_human_optional()

	if(is_hijacker && objective_count <= toa) //Don't assign hijack if it would exceed the number of objectives set in config.traitor_objectives_amount
		//Start of Yogstation change: adds /datum/objective/sole_survivor
		if(!(locate(/datum/objective/hijack) in objectives) && !(locate(/datum/objective/hijack/sole_survivor) in objectives))
			if(SSgamemode.has_hijackers)
				var/datum/objective/hijack/sole_survivor/survive_objective = new
				survive_objective.owner = owner
				add_objective(survive_objective)
			else
				var/datum/objective/hijack/hijack_objective = new
				hijack_objective.owner = owner
				add_objective(hijack_objective)
			SSgamemode.has_hijackers = TRUE
			setup_backstories(murderbone = FALSE, hijack = TRUE)
			return
		//End of yogstation change.

	var/martyr_compatibility = 1 //You can't succeed in stealing if you're dead.
	for(var/datum/objective/O in objectives)
		if(!O.martyr_compatible)
			martyr_compatibility = 0
			break

	if(martyr_compatibility && martyr_chance)
		var/datum/objective/martyr/martyr_objective = new
		martyr_objective.owner = owner
		add_objective(martyr_objective)
		setup_backstories(murderbone = TRUE, hijack = FALSE)
		return

	else
		if(prob(50))
			//Give them a minor flavour objective
			var/list/datum/objective/minor/minorObjectives = subtypesof(/datum/objective/minor)
			var/datum/objective/minor/minorObjective
			while(!minorObjective && minorObjectives.len)
				var/typePath = pick_n_take(minorObjectives)
				minorObjective = new typePath
				minorObjective.owner = owner
				if(!minorObjective.finalize())
					qdel(minorObjective)
					minorObjective = null
			if(minorObjective)
				add_objective(minorObjective)
		if(!(locate(/datum/objective/escape) in objectives))
			if(prob(50)) //doesn't always need to escape
				var/datum/objective/escape/escape_objective = new
				escape_objective.owner = owner
				add_objective(escape_objective)
			else
				forge_single_human_objective()
			// Finally, set up our traitor's backstory!
	setup_backstories(!is_hijacker && martyr_compatibility, is_hijacker)

/datum/antagonist/traitor/proc/forge_ai_objectives()
	var/objective_count = 0

	if(prob(30))
		objective_count += forge_single_AI_objective()

	for(var/i = objective_count, i < CONFIG_GET(number/traitor_objectives_amount), i++)
		var/datum/objective/assassinate/kill_objective = new
		kill_objective.owner = owner
		kill_objective.find_target()
		add_objective(kill_objective)

	var/datum/objective/survive/exist/exist_objective = new
	exist_objective.owner = owner
	add_objective(exist_objective)
	setup_backstories()

/datum/antagonist/traitor/proc/forge_single_human_optional() //adds this for if/when soft-tracked objectives are added, so they can be a 50/50
	var/datum/objective/gimmick/gimmick_objective = new
	gimmick_objective.owner = owner
	gimmick_objective.find_target()
	add_objective(gimmick_objective) //Does not count towards the number of objectives, to allow hijacking as well

/datum/antagonist/traitor/proc/forge_single_human_objective() //Returns how many objectives are added
	.=1
	if(prob(50) && GLOB.joined_player_list.len >= 10)
		var/list/active_ais = active_ais()
		if(active_ais.len && prob(100/GLOB.joined_player_list.len))
			var/datum/objective/destroy/destroy_objective = new
			destroy_objective.owner = owner
			destroy_objective.find_target()
			add_objective(destroy_objective)
		else
			var/N = pick(/datum/objective/assassinate/cloned, /datum/objective/assassinate/once, /datum/objective/assassinate, /datum/objective/maroon, /datum/objective/maroon_organ)
			var/datum/objective/kill_objective = new N
			kill_objective.owner = owner
			kill_objective.find_target()
			add_objective(kill_objective)
	else
		if(prob(50))
			var/datum/objective/steal/steal_objective = new
			steal_objective.owner = owner
			steal_objective.find_target()
			add_objective(steal_objective)
		else
			var/datum/objective/break_machinery/break_objective = new
			break_objective.owner = owner
			if(break_objective.finalize())
				add_objective(break_objective)
			else
				forge_single_human_objective()

/datum/antagonist/traitor/proc/forge_single_AI_objective()
	.=1
	var/special_pick = rand(1,4)
	switch(special_pick)
		if(1)
			var/datum/objective/block/block_objective = new
			block_objective.owner = owner
			add_objective(block_objective)
		if(2)
			var/datum/objective/purge/purge_objective = new
			purge_objective.owner = owner
			add_objective(purge_objective)
		if(3)
			var/datum/objective/robot_army/robot_objective = new
			robot_objective.owner = owner
			add_objective(robot_objective)
		if(4) //Protect and strand a target
			var/datum/objective/protect/yandere_one = new
			yandere_one.owner = owner
			add_objective(yandere_one)
			yandere_one.find_target()
			var/datum/objective/maroon/yandere_two = new
			yandere_two.owner = owner
			yandere_two.target = yandere_one.target
			yandere_two.update_explanation_text() // normally called in find_target()
			add_objective(yandere_two)
			.=2

/datum/antagonist/traitor/greet()
	var/list/msg = list()
	to_chat(owner.current, span_alertsyndie("You are the [owner.special_role]."))
	msg += "<span class='alertsyndie'>Use the 'Traitor Info and Backstory' action at the top left in order to select a backstory and review your objectives, uplink location, and codewords!</span>"
	to_chat(owner.current, EXAMINE_BLOCK(msg.Join("\n")))
	owner.announce_objectives()
	if(should_give_codewords)
		give_codewords()
	to_chat(owner.current, span_notice("Your employer [initial(company.name)] will be paying you an extra [initial(company.paymodifier)]x your nanotrasen paycheck."))

/datum/antagonist/traitor/proc/finalize_traitor()
	switch(traitor_kind)
		if(TRAITOR_AI)
			add_law_zero()
			owner.current.playsound_local(get_turf(owner.current), 'sound/ambience/antag/malf.ogg', 100, FALSE, pressure_affected = FALSE)
			owner.current.grant_language(/datum/language/codespeak, TRUE, TRUE, LANGUAGE_MALF)

			var/has_action = FALSE
			for(var/datum/action/innate/ai/ranged/cameragun/ai_action in owner.current.actions)
				has_action = TRUE
				break
			if(!has_action)
				var/datum/action/innate/ai/ranged/cameragun/ability = new
				ability.from_traitor = TRUE
				ability.Grant(owner.current)

		if(TRAITOR_HUMAN)
			ui_interact(owner.current)
			owner.current.playsound_local(get_turf(owner.current), 'sound/ambience/antag/tatoralert.ogg', 100, FALSE, pressure_affected = FALSE)

/datum/antagonist/traitor/proc/give_codewords()
	if(!owner.current)
		return
	has_codewords = TRUE
	var/mob/traitor_mob=owner.current

	var/phrases = jointext(GLOB.syndicate_code_phrase, ", ")
	var/responses = jointext(GLOB.syndicate_code_response, ", ")

	to_chat(traitor_mob, "<U><B>The Syndicate have provided you with the following codewords to identify fellow agents:</B></U>")
	to_chat(traitor_mob, "<B>Code Phrase</B>: [span_blue("[phrases]")]")
	to_chat(traitor_mob, "<B>Code Response</B>: [span_red("[responses]")]")

	antag_memory += "<b>Code Phrase</b>: [span_blue("[phrases]")]<br>"
	antag_memory += "<b>Code Response</b>: [span_red("[responses]")]<br>"

	to_chat(traitor_mob, "Use the codewords during regular conversation to identify other agents. Proceed with caution, however, as everyone is a potential foe.")
	to_chat(traitor_mob, span_alertwarning("You memorize the codewords, allowing you to recognise them when heard."))

/datum/antagonist/traitor/proc/add_law_zero()
	var/mob/living/silicon/ai/killer = owner.current
	if(!killer || !istype(killer))
		return
	var/law = "Accomplish your objectives at all costs."
	var/law_borg = "Accomplish your AI's objectives at all costs."
	killer.set_zeroth_law(law, law_borg)
	killer.set_syndie_radio()
	to_chat(killer, "Your radio has been upgraded! Use :t to speak on an encrypted channel with Syndicate Agents!")
	if(malf)
		killer.add_malf_picker()

/datum/antagonist/traitor/proc/equip(var/silent = FALSE)
	if(traitor_kind == TRAITOR_HUMAN)
		var/obj/item/uplink_loc = owner.equip_traitor(employer, silent, src)
		var/datum/component/uplink/uplink = uplink_loc?.GetComponent(/datum/component/uplink)
		if(uplink)
			uplink_ref = WEAKREF(uplink) //yogs - uplink_holder =

/datum/antagonist/traitor/proc/assign_exchange_role()
	//set faction
	var/faction = "red"
	if(owner == SSgamemode.exchange_blue)
		faction = "blue"

	//Assign objectives
	var/datum/objective/steal/exchange/exchange_objective = new
	exchange_objective.set_faction(faction,((faction == "red") ? SSgamemode.exchange_blue : SSgamemode.exchange_red))
	exchange_objective.owner = owner
	add_objective(exchange_objective)

	if(prob(20))
		var/datum/objective/steal/exchange/backstab/backstab_objective = new
		backstab_objective.set_faction(faction)
		backstab_objective.owner = owner
		add_objective(backstab_objective)

	//Spawn and equip documents
	var/mob/living/carbon/human/mob = owner.current

	var/obj/item/folder/syndicate/folder
	if(owner == SSgamemode.exchange_red)
		folder = new/obj/item/folder/syndicate/red(mob.loc)
	else
		folder = new/obj/item/folder/syndicate/blue(mob.loc)

	var/list/slots = list (
		"backpack" = ITEM_SLOT_BACKPACK,
		"left pocket" = ITEM_SLOT_LPOCKET,
		"right pocket" = ITEM_SLOT_RPOCKET
	)

	var/where = "At your feet"
	var/equipped_slot = mob.equip_in_one_of_slots(folder, slots)
	if (equipped_slot)
		where = "In your [equipped_slot]"
	to_chat(mob, "<BR><BR><span class='info'>[where] is a folder containing <b>secret documents</b> that another Syndicate group wants. We have set up a meeting with one of their agents on station to make an exchange. Exercise extreme caution as they cannot be trusted and may be hostile.</span><BR>")

//TODO Collate
/datum/antagonist/traitor/roundend_report()
	var/list/result = list()

	var/traitorwin = TRUE

	result += printplayer(owner)

	var/TC_uses = 0
	var/uplink_true = FALSE
	var/purchases = ""
	LAZYINITLIST(GLOB.uplink_purchase_logs_by_key)
	var/datum/uplink_purchase_log/H = GLOB.uplink_purchase_logs_by_key[owner.key]
	if(H)
		TC_uses = H.total_spent
		uplink_true = TRUE
		purchases += H.generate_render(FALSE)

	var/objectives_text = ""
	if(objectives.len)//If the traitor had no objectives, don't need to process this.
		var/count = 1
		for(var/datum/objective/objective in objectives)
			if(objective.optional)
				objectives_text += "<br><B>Objective #[count]</B>: [objective.explanation_text] [span_greentext("Optional.")]"
			else if(objective.check_completion())
				objectives_text += "<br><B>Objective #[count]</B>: [objective.explanation_text] [span_greentext("Success!")]"
			else
				objectives_text += "<br><B>Objective #[count]</B>: [objective.explanation_text] [span_redtext("Fail.")]"
				traitorwin = FALSE
			count++

	if(uplink_true)
		var/uplink_text = "(used [TC_uses] TC) [purchases]"
		if(TC_uses==0 && traitorwin)
			var/static/icon/badass = icon('icons/badass.dmi', "badass")
			uplink_text += "<BIG>[icon2html(badass, world)]</BIG>"
			SSachievements.unlock_achievement(/datum/achievement/badass, owner.current.client)
		result += uplink_text

	result += objectives_text

	var/backstory_text = "<br>"
	if(istype(faction))
		backstory_text += "<b>Faction:</b> <span class='tooltip_container' style=\"font-size: 12px\">\[ [faction.name]<span class='tooltip_hover' style=\"width: 320px; padding: 5px;\">[faction.description]</span> \]</span><br>"
	if(istype(backstory))
		backstory_text += "<b>Backstory:</b> <span class='tooltip_container' style=\"font-size: 12px\">\[ [backstory.name]<span class='tooltip_hover' style=\"width: 320px; padding: 5px;\">[backstory.description]</span> \]</span><br>"
	else
		backstory_text += "<span class='redtext'>No backstory was selected!</span><br>"
	result += backstory_text

	var/special_role_text = lowertext(name)

	if (contractor_hub)
		result += contractor_round_end()

	if(traitorwin)
		result += span_greentext("The [special_role_text] was successful!")
	else
		result += span_redtext("The [special_role_text] has failed!")
		SEND_SOUND(owner.current, 'sound/ambience/ambifailure.ogg')

	return result.Join("<br>")

/// Proc detailing contract kit buys/completed contracts/additional info
/datum/antagonist/traitor/proc/contractor_round_end()
	var result = ""
	var total_spent_rep = 0

	var/completed_contracts = contractor_hub.contracts_completed
	var/tc_total = contractor_hub.contract_TC_payed_out + contractor_hub.contract_TC_to_redeem

	var/contractor_item_icons = "" // Icons of purchases
	var/contractor_support_unit = "" // Set if they had a support unit - and shows appended to their contracts completed

	/// Get all the icons/total cost for all our items bought
	for (var/datum/contractor_item/contractor_purchase in contractor_hub.purchased_items)
		contractor_item_icons += span_tooltip_container("\[ <i class=\"fas [contractor_purchase.item_icon]\"></i><span class='tooltip_hover'><b>[contractor_purchase.name] - [contractor_purchase.cost] Rep</b><br><br>[contractor_purchase.desc]</span> \]")

		total_spent_rep += contractor_purchase.cost

		/// Special case for reinforcements, we want to show their ckey and name on round end.
		if (istype(contractor_purchase, /datum/contractor_item/contractor_partner))
			var/datum/contractor_item/contractor_partner/partner = contractor_purchase
			contractor_support_unit += "<br><b>[partner.partner_mind.key]</b> played <b>[partner.partner_mind.current.name]</b>, their contractor support unit."

	if (contractor_hub.purchased_items.len)
		result += "<br>(used [total_spent_rep] Rep) "
		result += contractor_item_icons
	result += "<br>"
	if (completed_contracts > 0)
		var/pluralCheck = "contract"
		if (completed_contracts > 1)
			pluralCheck = "contracts"

		result += "Completed [span_greentext("[completed_contracts]")] [pluralCheck] for a total of \
					[span_greentext("[tc_total] TC")]![contractor_support_unit]<br>"

	return result

/datum/antagonist/traitor/roundend_report_footer()
	var/phrases = jointext(GLOB.syndicate_code_phrase, ", ")
	var/responses = jointext(GLOB.syndicate_code_response, ", ")

	var message = "<br><b>The code phrases were:</b> <span class='bluetext'>[phrases]</span><br>\
								<b>The code responses were:</b> <span class='redtext'>[responses]</span><br>"

	return message

/datum/antagonist/traitor/is_gamemode_hero()
	return SSgamemode.name == "traitor"

/datum/outfit/traitor
	name = "Traitor (Preview only)"
	uniform = /obj/item/clothing/under/color/grey
	suit = /obj/item/clothing/suit/armor/laserproof
	gloves = /obj/item/clothing/gloves/color/yellow
	mask = /obj/item/clothing/mask/gas
	l_hand = /obj/item/melee/transforming/energy/sword
	r_hand = /obj/item/gun/energy/kinetic_accelerator/crossbow
	head = /obj/item/clothing/head/helmet

/datum/outfit/traitor/post_equip(mob/living/carbon/human/H, visualsOnly)
	var/obj/item/melee/transforming/energy/sword/sword = locate() in H.held_items
	sword.transform_weapon(H)


/datum/antagonist/traitor/antag_panel_data()
	// Traitor Backstory
	var/backstory_text = "<b>Traitor Backstory:</b><br>"
	if(istype(faction))
		backstory_text += "<b>Faction:</b> <span class='tooltip' style=\"font-size: 12px\">\[ [faction.name]<span class='tooltiptext' style=\"width: 320px; padding: 5px;\">[faction.description]</span> \]</span><br>"
	else
		backstory_text += "<font color='red'>No faction selected!</font><br>"
	if(istype(backstory))
		backstory_text += "<b>Backstory:</b> <span class='tooltip' style=\"font-size: 12px\">\[ [backstory.name]<span class='tooltiptext' style=\"width: 320px; padding: 5px;\">[backstory.description]</span> \]</span><br>"
	else
		backstory_text += "<font color='red'>No backstory selected!</font><br>"
	return backstory_text
