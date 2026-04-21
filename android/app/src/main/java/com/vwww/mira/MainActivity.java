package com.vwww.mira;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.ViewGroup;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.TextView;

import java.io.File;

public final class MainActivity extends Activity {
    private MiraTerminalServer server;
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            MiraBootstrap bootstrap = new MiraBootstrap(this);
            bootstrap.installIfNeeded();

            server = new MiraTerminalServer(this, bootstrap, 0);
            server.start();
            setupWebView();
            String url = "http://127.0.0.1:" + server.getPort() + "/?token=" + server.getToken();
            if (BuildConfig.DEBUG) {
                Log.i("Mira", "Mira Web Terminal listening on " + url);
            }
            webView.loadUrl(url);
        } catch (Throwable throwable) {
            TextView errorView = new TextView(this);
            errorView.setText("Mira 启动失败\n\n" + throwable);
            errorView.setTextSize(14);
            errorView.setPadding(32, 32, 32, 32);
            setContentView(errorView);
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void setupWebView() {
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG);
        webView = new WebView(this);
        webView.setLayoutParams(new ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ));

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMediaPlaybackRequiresUserGesture(false);

        setContentView(webView);
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        if (server != null) {
            server.close();
            server = null;
        }
        super.onDestroy();
    }
}
