/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class SnTrayPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new SnTrayApplet(uuid);
	}
}

[GtkTemplate (ui="/org/buddiesofbudgie/sntray/settings.ui")]
public class SnTraySettings : Gtk.Grid {
	Settings? settings = null;

	[GtkChild]
	private unowned Gtk.SpinButton? spinbutton_spacing;

	public SnTraySettings(Settings? settings) {
		this.settings = settings;
		settings.bind("spacing", spinbutton_spacing, "value", SettingsBindFlags.DEFAULT);
	}
}

public class SnTrayApplet : Budgie.Applet {
	public string uuid { public set; public get; }
	private Settings? settings;
	private Gtk.EventBox box;
	private Gtk.Box layout;
	private Gtk.Orientation orient;
	private uint dbus_identifier;

	private static StatusNotifierWatcher? watcher;
	private static int ref_counter;

	public SnTrayApplet(string uuid) {
		Object(uuid: uuid);

		get_style_context().add_class("system-tray-applet");

		box = new Gtk.EventBox();
		add(box);

		settings_schema = "org.buddiesofbudgie.sntray";
		settings_prefix = "/org/buddiesofbudgie/budgie-panel/instance/sntray";

		settings = get_applet_settings(uuid);
		settings.changed["spacing"].connect((key) => {
			layout.set_spacing(settings.get_int("spacing"));
		});

		layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, settings.get_int("spacing"));
		box.add(layout);

		AtomicInt.inc(ref ref_counter);
		if (watcher == null) {
			watcher = new StatusNotifierWatcher();
		}

		watcher.status_notifier_item_registered_custom.connect((name,path)=>{
			try {
				StatusNotifierItem dbus_item = Bus.get_proxy_sync(BusType.SESSION, name, path);
				layout.add(new SnTrayItem(dbus_item));
			} catch (Error e) {
				warning("Failed to fetch dbus item info for name=%s and path=%s", name, path);
			}
		});

		string host_name = "org.freedesktop.StatusNotifierHost-budgie_" + uuid;

		dbus_identifier = Bus.own_name(
			BusType.SESSION,
			host_name,
			BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
			(conn,name)=>{
				try {
					watcher.register_status_notifier_host(host_name);
				} catch (Error e) {
					critical("Failed to register Status Notifier host: %s", e.message);
				}
			}
		);

		show_all();
	}

	~SnTrayApplet() {
		Bus.unown_name(dbus_identifier);

		// if this is the last applet left and it's being deleted, we don't need the watcher
		if (AtomicInt.dec_and_test(ref ref_counter)) {
			watcher = null;
		}
	}

	public override void panel_position_changed(Budgie.PanelPosition position) {
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			orient = Gtk.Orientation.VERTICAL;
		} else {
			orient = Gtk.Orientation.HORIZONTAL;
		}
	}

	public override bool supports_settings() {
		return true;
	}

	public override Gtk.Widget? get_settings_ui() {
		return new SnTraySettings(get_applet_settings(uuid));
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SnTrayPlugin));
}