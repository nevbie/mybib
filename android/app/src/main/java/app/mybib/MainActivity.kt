package app.mybib

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import app.mybib.ui.MybibTheme
import app.mybib.ui.Root
import kotlin.concurrent.thread

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val vm: AppViewModel = viewModel()
            MybibTheme { Root(vm) }
        }
    }

    override fun onStop() {
        super.onStop()
        // don't lose the debounced save when the app goes to the background
        val store = (application as MybibApp).store
        if (store.ready.value) thread { store.flush() }
    }
}
