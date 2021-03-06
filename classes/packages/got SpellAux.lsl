/*
	
	THIS SCRIPT IS SATURATED.
	ADDITIONS WILL LEAD TO STACK HEAPS

*/
#define USE_EVENTS
#include "got/_core.lsl"

integer TEAM = TEAM_PC;

// Contains the fx data
#define CSTRIDE 4
// This is the actual spell data cached
list CACHE;
#define spellWrapper(spellnr) llList2String(CACHE, spellnr*CSTRIDE+0)
#define spellSelfcast(spellnr) llList2String(CACHE, spellnr*CSTRIDE+1)
#define spellRange(spellnr) llList2Float(CACHE, spellnr*CSTRIDE+2)
#define spellFlags(spellnr) llList2Integer(CACHE, spellnr*CSTRIDE+3)

#define nrToIndex(nr) nr*CSTRIDE
//#define nrToData(nr) llList2List(CACHE, nr*CSTRIDE, nr*CSTRIDE+CSTRIDE-1)
#define difDmgMod() llPow(0.9, DIFFICULTY)

integer DIFFICULTY;

// Calculates bonus damage for particular spells
list SPELL_DMG_DONE_MOD = [-1,-1,-1,-1,-1];		// [rest, abil1, abil2...]

// Caching
float CACHE_AROUSAL;
float CACHE_PAIN;
float CACHE_CRIT;
float CACHE_MAX_HP = 100;

list PLAYERS;

integer STATUS_FLAGS;

// FX
float dmdmod = 1;       // Damage done
float critmod = 0;
float cdmod = 1;		// Cooldown modifier
float hdmod = 1;		// Healing done mod
list manacostMulti = [1,1,1,1,1];

float befuddle = 1;		// Chance to cast at a random target
float backstabMulti = 1;	// Additional damage when attacking from behind
integer fxFlags = 0;

#define aroused (1-(float)(STATUS_FLAGS&StatusFlag$aroused)/StatusFlag$aroused*.1)
#define pmod (1./count(PLAYERS))

string runMath(string FX, integer index, key targ){
    list split = llParseString2List(FX, ["$MATH$"], []);
	parseFxFlags(targ, fxf)
	
	float bsMul = 1;
	integer B = 0;
	myAngZ(targ, ang)
	if((llFabs(ang)>PI_BY_TWO || fxf & fx$F_ALWAYS_BACKSTABBED || fxFlags&fx$F_ALWAYS_BEHIND) && targ != ""){
		B = 1;
		bsMul = backstabMulti;
	}
	float spdmdm = llList2Float(SPELL_DMG_DONE_MOD, index);
	if(spdmdm == -1)spdmdm = 1;
	else if(spdmdm<0)spdmdm = 0;

	string consts = llList2Json(JSON_OBJECT, [
		// Damage done multiplier
        "D", (dmdmod*pmod*aroused*CACHE_CRIT*spdmdm*difDmgMod()*bsMul),
		// Raw multiplier not affected by team or difficulty
		"R", (dmdmod*aroused*CACHE_CRIT*spdmdm*bsMul),
		// Critical hit
		"C", CACHE_CRIT,
		// Points of arousal
		"A", CACHE_AROUSAL,
		// Points of pain
		"P", CACHE_PAIN,
		// Backstab boolean
		"B", B,
		// Cooldown modifier
		"H", cdmod,
		// Spell damage done mod for index, added into D
		"M", spdmdm,
		// HEaling done multiplier
		"h", hdmod,
		"T", TEAM,
		// Max HP
		"mhp", CACHE_MAX_HP
    ]);

    integer i;
    for(i=1; i<llGetListLength(split); i++){
        split = llListReplaceList(split, [llGetSubString(llList2String(split, i-1), 0, -2)], i-1, i-1);
        string block = llList2String(split, i);
        integer q = llSubStringIndex(block, "\"");
        string math = implode("/", explode("\\/", llGetSubString(block, 0, q-1)));
		float out = mathToFloat(math, 0, consts);
        block = llGetSubString(block, q+1, -1);
		split = llListReplaceList(split, [(string)out+block], i, i);
    }
    return llDumpList2String(split, "");
}

onEvt(string script, integer evt, list data){

    if(script == "#ROOT" && evt == RootEvt$players)
        PLAYERS = data;

	else if(script == "got Status" && evt == StatusEvt$flags)
        STATUS_FLAGS = llList2Integer(data,0);
	
	else if(script == "got Status" && evt == StatusEvt$difficulty){
		DIFFICULTY = l2i(data, 0);
	}
	
	else if(script == "got Status" && evt == StatusEvt$resources){
		// [(float)dur, (float)max_dur, (float)mana, (float)max_mana, (float)arousal, (float)max_arousal, (float)pain, (float)max_pain] - PC only
		CACHE_AROUSAL = llList2Float(data, 4);
		CACHE_PAIN = llList2Float(data, 6);
		CACHE_MAX_HP = l2f(data, 1);
	}
	else if(script == "got Status" && evt == StatusEvt$team)
		TEAM = l2i(data,0);
	
	else if(script == "got FXCompiler" && evt == FXCEvt$spellMultipliers){
		SPELL_DMG_DONE_MOD = llJson2List(llList2String(data,0));
		manacostMulti = llJson2List(llList2String(data,1));
	}
	
	else if(script == "got SpellMan" && evt == SpellManEvt$recache){
		CACHE = [];

		integer i;
		for(i=0; i<5; i++){
			
			list d = llJson2List(db3$get(BridgeSpells$name+"_temp"+(str)i, []));
			if(d == [])
				d = llJson2List(db3$get(BridgeSpells$name+(str)i, []));
			
			
			CACHE+= llList2String(d, 2); // Wrapper
			CACHE+= llList2String(d, 9); // Selfcast
			CACHE+= llList2Float(d, 6); // Range
			CACHE+= llList2Integer(d, 5); // Flags

		}
		
	}
	
	// Spell handlers
	/*
    else if(script == "got SpellMan" && evt == SpellManEvt$cast){
        
    }
	*/
    else if(script == "got SpellMan" && evt == SpellManEvt$complete){
		
		integer SPELL_CASTED = l2i(data, 0);                    // Spell casted index 0-4
        list SPELL_TARGS = llJson2List(l2s(data, 3));                    // Targets casted at
		
		
		integer flags = spellFlags(SPELL_CASTED);
		
		CACHE_CRIT = 1;
		if(llFrand(1)<critmod && ~flags&SpellMan$NO_CRITS){
			CACHE_CRIT = 2;
			llTriggerSound("e713ffed-c518-b1ed-fcde-166581c6ad17", .25);
		}
		
		// RunMath should be done against certain targets for backstab to work

		// Handle AOE
		if((string)SPELL_TARGS == "AOE"){
			FX$aoe(spellRange(SPELL_CASTED), llGetKey(), runMath(spellWrapper(SPELL_CASTED),SPELL_CASTED, ""), TEAM);  
			SPELL_TARGS = [LINK_ROOT];
		}
		
		else if(llFrand(1) < befuddle-1){
			float r = spellRange(SPELL_CASTED);
			string targ = randElem(PLAYERS);
			if(targ == llGetOwner())
				SPELL_TARGS = [LINK_ROOT];
			else if(llVecDist(llGetPos(), prPos(targ)) < r){
				SPELL_TARGS = [targ];
			}
		}
		
		// Send effects and rez visuals
		list_shift_each(SPELL_TARGS, val, 
			
			if(val == llGetKey() || val == llGetOwner())
				val = (str)LINK_ROOT;
						
			if((string)SPELL_TARGS != "AOE"){
				FX$send(val, llGetKey(), runMath(spellWrapper(SPELL_CASTED),SPELL_CASTED, val), TEAM);
			}
		)
		
		if(llStringLength(spellSelfcast(SPELL_CASTED)) > 2)
			FX$run(llGetOwner(), runMath(spellSelfcast(SPELL_CASTED), SPELL_CASTED, ""));
		
    }
	/*
    else if(script == "got SpellMan" && evt == SpellManEvt$interrupted){
        
    }
	*/
}




default
{
	state_entry(){
		PLAYERS = [(str)llGetOwner()];
		
	}
	
	#define LM_PRE \
	if(nr == TASK_FX){ \
		list data = llJson2List(s); \
		dmdmod = i2f(l2f(data, FXCUpd$DAMAGE_DONE)); \
		critmod = i2f(l2f(data, FXCUpd$CRIT)); \
		cdmod = i2f(l2f(data, FXCUpd$COOLDOWN)); \
		hdmod = i2f(l2f(data, FXCUpd$HEAL_DONE_MOD)); \
		fxFlags = l2i(data, FXCUpd$FLAGS);\
		befuddle = i2f(l2f(data, FXCUpd$BEFUDDLE));\
		backstabMulti = i2f(l2f(data,FXCUpd$BACKSTAB_MULTI)); \
	}
	
	
    // This is the standard linkmessages
    #include "xobj_core/_LM.lsl" 
    /*
        Included in all these calls:
        METHOD - (int)method  
        PARAMS - (var)parameters 
        SENDER_SCRIPT - (var)parameters
        CB - The callback you specified when you sent a task 
    */  
    #define LM_BOTTOM  
    #include "xobj_core/_LM.lsl"  
}

