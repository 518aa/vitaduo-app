package com.vitaduo.datedrop

import android.app.Application
import com.vitaduo.datedrop.network.NetworkManager

class DateDropApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NetworkManager.init(this)
    }
}
