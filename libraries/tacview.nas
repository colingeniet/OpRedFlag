# Copyright by Justin Nicholson (aka Pinto)
# Released under the GNU General Public License version 2.0
#
# Authors: Pinto, Nikolai V. Chr., Colin Geniet

# Short installation instructions:
# - Add and load this file in the 'tacview' namespace.
# - Adjust the four parameters just below.
# - Set property /payload/d-config/tacview_supported=1
# - Ensure the radar code sets 'tacobj' fields properly.
#   In Nikolai/Richard generic 'radar-system.nas',
#   this simply requires setting 'enable_tacobject=1'.
# - Add some way to start/stop recording.

### Parameters to adjust (example values from the F-16)

# Aircraft type string for tacview
var tacview_ac_type = getprop("sim/variant-id") < 3 ? "F-16A" : "F-16C";
# Aircraft type as inserted in the output file name
var filename_ac_type = "f16";

# Function returning an array of "contact" objects, containing all aicrafts tacview is to show.
# A contact object must
# - implement the API specified by missile-code.nas
# - have a getModel() method, which will be used as aircraft type designator in tacview.
# - contain a field 'tacobj', which must be an instance of the 'tacobj' class below,
#   and have the 'tacviewID' and 'valid' fields set appropriately.
#
var get_contacts_list = func {
    return radar_system.getCompleteList();
}

# Function returning the focused/locked aircraft, as a "contact" object (or nil).
var get_primary_contact = func {
    return radar_system.apg68Radar.getPriorityTarget();
}

# Radar range. May return nil if n/a
var get_radar_range_nm = func {
    return getprop("instrumentation/radar/radar2-range");
}

### End of parameters


var main_update_rate = 0.3;
var write_rate = 10;

var outstr = "";

var timestamp = "";
var output_file = "";
var f = "";
var myplaneID = int(rand()*10000);
var starttime = 0;
var writetime = 0;

var seen_ids = [];

var tacobj = {
    tacviewID: 0,
    lat: 0,
    lon: 0,
    alt: 0,
    roll: 0,
    pitch: 0,
    heading: 0,
    speed: -1,
    valid: 0,
};

var lat = 0;
var lon = 0;
var alt = 0;
var roll = 0;
var pitch = 0;
var heading = 0;
var speed = 0;
var mutexWrite = thread.newlock();

var startwrite = func() {
    if (starttime)
        return;

    timestamp = getprop("/sim/time/utc/year") ~ "-" ~ getprop("/sim/time/utc/month") ~ "-" ~ getprop("/sim/time/utc/day") ~ "T";
    timestamp = timestamp ~ getprop("/sim/time/utc/hour") ~ ":" ~ getprop("/sim/time/utc/minute") ~ ":" ~ getprop("/sim/time/utc/second") ~ "Z";
    var filetimestamp = string.replace(timestamp,":","-");
    output_file = getprop("/sim/fg-home") ~ "/Export/tacview-" ~ filename_ac_type ~ "-" ~ filetimestamp ~ ".acmi";
    # create the file
    f = io.open(output_file, "w");
    io.close(f);
    var color = ",Color=Blue";
    if (left(getprop("sim/multiplay/callsign"),5)=="OPFOR") {
        color=",Color=Red";
    }
    var meta = sprintf(",DataSource=FlightGear %s,DataRecorder=%s v%s", getprop("sim/version/flightgear"), getprop("sim/description"), getprop("sim/aircraft-version"));
    thread.lock(mutexWrite);
    write("FileType=text/acmi/tacview\nFileVersion=2.1\n");
    write("0,ReferenceTime=" ~ timestamp ~ meta ~ "\n#0\n");
    write(myplaneID ~ ",T=" ~ getLon() ~ "|" ~ getLat() ~ "|" ~ getAlt() ~ "|" ~ getRoll() ~ "|" ~ getPitch() ~ "|" ~ getHeading() ~ ",Name="~tacview_ac_type~",CallSign="~getprop("/sim/multiplay/callsign")~color~"\n"); #
    thread.unlock(mutexWrite);
    starttime = systime();
    setprop("/sim/screen/black","Starting Tacview recording");
    main_timer.start();
}

var stopwrite = func() {
    main_timer.stop();
    setprop("/sim/screen/black","Stopping Tacview recording");
    writetofile();
    starttime = 0;
    seen_ids = [];
    explo_arr = [];
    explosion_timeout_loop(1);
}

var mainloop = func() {
    if (!starttime) {
        main_timer.stop();
        return;
    }
    if (systime() - writetime > write_rate) {
        writetofile();
    }
    thread.lock(mutexWrite);
    write("#" ~ (systime() - starttime)~"\n");
    thread.unlock(mutexWrite);
    writeMyPlanePos();
    writeMyPlaneAttributes();
    foreach (var cx; get_contacts_list()) {
        if(cx.get_type() == armament.ORDNANCE) {
            continue;
        }
        if (cx["prop"] != nil and cx.prop.getName() == "multiplayer" and getprop("sim/multiplay/txhost") == "mpserver.opredflag.com") {
            continue;
        }
        var color = ",Color=Blue";
        if (left(cx.get_Callsign(),5)=="OPFOR" or left(cx.get_Callsign(),4)=="OPFR") {
            color=",Color=Red";
        }
        thread.lock(mutexWrite);
        if (find_in_array(seen_ids, cx.tacobj.tacviewID) == -1) {
            append(seen_ids, cx.tacobj.tacviewID);
            var model_is = cx.getModel();
            if (model_is=="Mig-28") {
                model_is = tacview_ac_type;
                color=",Color=Red";
            }
            write(cx.tacobj.tacviewID ~ ",Name="~ model_is~ ",CallSign=" ~ cx.get_Callsign() ~color~"\n")
        }
        if (cx.tacobj.valid) {
            var cxC = cx.getCoord();
            lon = cxC.lon();
            lat = cxC.lat();
            alt = cxC.alt();
            roll = cx.get_Roll();
            pitch = cx.get_Pitch();
            heading = cx.get_heading();
            speed = cx.get_Speed()*KT2MPS;

            write(cx.tacobj.tacviewID ~ ",T=");
            if (lon != cx.tacobj.lon) {
                write(sprintf("%.6f",lon));
                cx.tacobj.lon = lon;
            }
            write("|");
            if (lat != cx.tacobj.lat) {
                write(sprintf("%.6f",lat));
                cx.tacobj.lat = lat;
            }
            write("|");
            if (alt != cx.tacobj.alt) {
                write(sprintf("%.1f",alt));
                cx.tacobj.alt = alt;
            }
            write("|");
            if (roll != cx.tacobj.roll) {
                write(sprintf("%.1f",roll));
                cx.tacobj.roll = roll;
            }
            write("|");
            if (pitch != cx.tacobj.pitch) {
                write(sprintf("%.1f",pitch));
                cx.tacobj.pitch = pitch;
            }
            write("|");
            if (heading != cx.tacobj.heading) {
                write(sprintf("%.1f",heading));
                cx.tacobj.heading = heading;
            }
            if (speed != cx.tacobj.speed) {
                write(sprintf(",TAS=%.1f",speed));
                cx.tacobj.speed = speed;
            }
            write("\n");
        }
        thread.unlock(mutexWrite);
    }
    explosion_timeout_loop();
}

var main_timer = maketimer(main_update_rate, mainloop);


var writeMyPlanePos = func() {
    thread.lock(mutexWrite);
    write(myplaneID ~ ",T=" ~ getLon() ~ "|" ~ getLat() ~ "|" ~ getAlt() ~ "|" ~ getRoll() ~ "|" ~ getPitch() ~ "|" ~ getHeading() ~ "\n");
    thread.unlock(mutexWrite);
}

var writeMyPlaneAttributes = func() {
    var tgt = "";
    var contact = get_primary_contact();
    if (contact != nil) {
        tgt= ",FocusedTarget="~contact.tacobj.tacviewID;
    }
    var rmode = ",RadarMode=1";
    if (getprop("sim/multiplay/generic/int[2]")) {
        rmode = ",RadarMode=0";
    }
    var rrange = get_radar_range_nm();
    if (rrange != nil) {
        rrange = ",RadarRange="~math.round(get_radar_range_nm()*NM2M,1);
    } else {
        rrange = "";
    }
    var fuel = ",FuelWeight="~math.round(0.4535*getprop("/consumables/fuel/total-fuel-lbs"),1);
    var gear = ",LandingGear="~math.round(getprop("gear/gear[0]/position-norm"),0.01);
    var str = myplaneID ~ fuel~rmode~rrange~gear~",TAS="~getTas()~",CAS="~getCas()~",Mach="~getMach()~",AOA="~getAoA()~",HDG="~getHeading()~tgt~",VerticalGForce="~getG()~"\n";#",Throttle="~getThrottle()~",Afterburner="~getAfterburner()~
    thread.lock(mutexWrite);
    write(str);
    thread.unlock(mutexWrite);
}

var explo = {
    tacviewID: 0,
    time: 0,
};

var explo_arr = [];

# needs threadlocked before calling
var writeExplosion = func(lat,lon,altm,rad) {
    var e = {parents:[explo]};
    e.tacviewID = 21000 + int(math.floor(rand()*20000));
    e.time = systime();
    append(explo_arr, e);
    write("#" ~ (systime() - starttime)~"\n");
    write(e.tacviewID ~",T="~lon~"|"~lat~"|"~altm~",Radius="~rad~",Type=Explosion\n");
}

var explosion_timeout_loop = func(all = 0) {
    foreach(var e; explo_arr) {
        if (e.time) {
            if (systime() - e.time > 15 or all) {
                thread.lock(mutexWrite);
                write("#" ~ (systime() - starttime)~"\n");
                write("-"~e.tacviewID);
                thread.unlock(mutexWrite);
                e.time = 0;
            }
        }
    }
}

var write = func(str) {
    outstr = outstr ~ str;
}

var writetofile = func() {
    if (outstr == "") {
        return;
    }
    writetime = systime();
    f = io.open(output_file, "a");
    io.write(f, outstr);
    io.close(f);
    outstr = "";
}

var getLat = func() {
    return getprop("/position/latitude-deg");
}

var getLon = func() {
    return getprop("/position/longitude-deg");
}

var getAlt = func() {
    return math.round(getprop("/position/altitude-ft") * FT2M,0.01);
}

var getRoll = func() {
    return math.round(getprop("/orientation/roll-deg"),0.01);
}

var getPitch = func() {
    return math.round(getprop("/orientation/pitch-deg"),0.01);
}

var getHeading = func() {
    return math.round(getprop("/orientation/heading-deg"),0.01);
}

var getTas = func() {
    return math.round(getprop("fdm/jsbsim/velocities/vtrue-kts") * KT2MPS,1.0);
}

var getCas = func() {
    return math.round(getprop("fdm/jsbsim/velocities/vc-kts") * KT2MPS,1.0);
}

var getMach = func() {
    return math.round(getprop("/velocities/mach"),0.001);
}

var getAoA = func() {
    return math.round(getprop("/orientation/alpha-deg"),0.01);
}

var getG = func() {
    getprop("accelerations/pilot-g");
}

#var getThrottle = func() {
#    return math.round(getprop("velocities/thrust"),0.01);
#}

#var getAfterburner = func() {
#    return getprop("velocities/thrust")>0.61*0.61;
#}

var find_in_array = func(arr,val) {
    forindex(var i; arr) {
        if ( arr[i] == val ) {
            return i;
        }
    }
    return -1;
}

#setlistener("/controls/armament/pickle", func() {
#    if (!starttime) {
#        return;
#    }
#    thread.lock(mutexWrite);
#    write("#" ~ (systime() - starttime)~"\n");
#    write("0,Event=Message|"~ myplaneID ~ "|Pickle, selection at " ~ (getprop("controls/armament/pylon-knob") + 1) ~ "\n");
#    thread.unlock(mutexWrite);
#},0,0);

setlistener("/controls/armament/trigger", func(p) {
    if (!starttime) {
        return;
    }
    thread.lock(mutexWrite);
    if (p.getValue()) {
        write("#" ~ (systime() - starttime)~"\n");
        write("0,Event=Message|"~ myplaneID ~ "|Trigger pressed.\n");
    } else {
        write("#" ~ (systime() - starttime)~"\n");
        write("0,Event=Message|"~ myplaneID ~ "|Trigger released.\n");
    }
    thread.unlock(mutexWrite);
},0,0);

setlistener("/sim/multiplay/chat-history", func(p) {
    if (!starttime) {
        return;
    }
    var hist_vector = split("\n",p.getValue());
    if (size(hist_vector) > 0) {
        var last = hist_vector[size(hist_vector)-1];
        last = string.replace(last,",",chr(92)~chr(44));#"\x5C"~"\x2C"
        thread.lock(mutexWrite);
        write("#" ~ (systime() - tacview.starttime)~"\n");
        write("0,Event=Message|Chat ["~last~"]\n");
        thread.unlock(mutexWrite);
    }
},0,0);


var msg = func (txt) {
    if (!starttime) {
        return;
    }
    thread.lock(mutexWrite);
    write("#" ~ (systime() - tacview.starttime)~"\n");
    write("0,Event=Message|"~myplaneID~"|AI ["~txt~"]\n");
    thread.unlock(mutexWrite);
}

setlistener("damage/sounds/explode-on", func(p) {
    if (!starttime) {
        return;
    }

    if (p.getValue()) {
        thread.lock(mutexWrite);
        write("#" ~ (systime() - tacview.starttime)~"\n");
        write("0,Event=Destroyed|"~myplaneID~"\n");
        thread.unlock(mutexWrite);
    }
},0,0);
