package com.vwww.mira;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private static final String PREFS = "mira_ui";
    private static final String KEY_DEVICE_NAME = "device_name";
    private static final String KEY_RELAY_URL = "relay_url";

    private MiraIdentity identity;
    private EditText deviceNameInput;
    private EditText relayUrlInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        identity = new MiraIdentity(this);
        showControlPage();
    }

    private void showControlPage() {
        SharedPreferences preferences = getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ScrollView scrollView = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(36, 36, 36, 36);
        scrollView.addView(root);

        TextView title = new TextView(this);
        title.setText("Mira by vw2x");
        title.setTextSize(24);
        root.addView(title);

        deviceNameInput = input("Device Name", preferences.getString(KEY_DEVICE_NAME, identity.defaultDeviceName()));
        relayUrlInput = input("Relay URL", preferences.getString(KEY_RELAY_URL, ""));
        root.addView(deviceNameInput);
        root.addView(relayUrlInput);

        Button start = new Button(this);
        start.setText("Connect Relay");
        start.setOnClickListener(view -> connectRelay());
        root.addView(start);

        Button stop = new Button(this);
        stop.setText("Disconnect");
        stop.setOnClickListener(view -> disconnectRelay());
        root.addView(stop);

        setContentView(scrollView);
    }

    private EditText input(String hint, String value) {
        EditText editText = new EditText(this);
        editText.setHint(hint);
        editText.setText(value);
        editText.setSingleLine(true);
        editText.setPadding(0, 18, 0, 18);
        return editText;
    }

    private void connectRelay() {
        String deviceName = deviceNameInput.getText().toString().trim();
        String relayUrl = relayUrlInput.getText().toString().trim();
        if (relayUrl.isEmpty()) return;
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_DEVICE_NAME, deviceName)
            .putString(KEY_RELAY_URL, relayUrl)
            .apply();

        Intent intent = new Intent(this, MiraDiscoveryService.class);
        intent.setAction(MiraDiscoveryService.ACTION_START);
        intent.putExtra(MiraDiscoveryService.EXTRA_DEVICE_NAME, deviceName);
        intent.putExtra(MiraDiscoveryService.EXTRA_RELAY_URL, relayUrl);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent);
        else startService(intent);
    }

    private void disconnectRelay() {
        Intent intent = new Intent(this, MiraDiscoveryService.class);
        intent.setAction(MiraDiscoveryService.ACTION_STOP);
        startService(intent);
    }
}
