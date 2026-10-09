@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package app.mybib.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalLibrary
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.LocalLibrary
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.mybib.AppViewModel
import app.mybib.Screen

@Composable
fun Root(vm: AppViewModel) {
    val items by vm.store.items.collectAsStateWithLifecycle()
    val settings by vm.store.settings.collectAsStateWithLifecycle()
    val ready by vm.store.ready.collectAsStateWithLifecycle()
    val ui = Ui(vm, items, settings, langOf(settings))
    val view = LocalView.current
    LaunchedEffect(vm.keepScreenOn) { view.keepScreenOn = vm.keepScreenOn }
    CompositionLocalProvider(LocalUi provides ui) {
        if (!ready) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(ui.t("app.loading")) }
        } else {
            val top = vm.stack.lastOrNull()
            BackHandler(enabled = top != null) { vm.pop() }
            if (top == null) {
                Home()
            } else {
                key(top) {
                    when (top) {
                        is Screen.Detail -> ItemScreen(top)
                        is Screen.Form -> ItemForm(top)
                        is Screen.Search -> SearchScreen(top)
                        is Screen.Scan -> ScanScreen(top)
                        is Screen.Photo -> PhotoScreen(top)
                        is Screen.Bulk -> BulkScreen(top)
                    }
                }
            }
        }
        DialogHost(vm.dialogs)
    }
}

@Composable
private fun Home() {
    val ui = LocalUi.current
    val vm = ui.vm
    val toCheck = ui.items.any { it.needsCheck }
    class NavTab(val icon: ImageVector, val selectedIcon: ImageVector, val label: String, val badge: Boolean = false)
    val tabs = listOf(
        NavTab(Icons.Outlined.LocalLibrary, Icons.Filled.LocalLibrary, ui.t("nav.library"), toCheck),
        NavTab(Icons.Outlined.AddCircleOutline, Icons.Filled.AddCircle, ui.t("nav.add")),
        NavTab(Icons.Outlined.Home, Icons.Filled.Home, ui.t("nav.places")),
        NavTab(Icons.Outlined.Settings, Icons.Filled.Settings, ui.t("nav.settingsShort")),
    )
    Scaffold(bottomBar = {
        NavigationBar {
            tabs.forEachIndexed { n, t ->
                NavigationBarItem(
                    selected = vm.tab == n,
                    onClick = { vm.tab = n },
                    icon = {
                        BadgedBox(badge = { if (t.badge) Badge() }) {
                            Icon(if (vm.tab == n) t.selectedIcon else t.icon, contentDescription = null)
                        }
                    },
                    label = { Text(t.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                )
            }
        }
    }) { padding ->
        Box(Modifier.padding(padding).consumeWindowInsets(padding).imePadding()) {
            when (vm.tab) {
                0 -> LibraryScreen()
                1 -> AddScreen()
                2 -> PlacesScreen()
                else -> SettingsScreen()
            }
        }
    }
}

/** Scaffold for screens on top of the tabs: back arrow, title, actions, optional bottom bar. */
@Composable
fun SubScreen(
    title: String,
    actions: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    content: @Composable () -> Unit,
) {
    val vm = LocalUi.current.vm
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = { vm.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = LocalUi.current.t("close")) } },
                actions = { actions() },
            )
        },
        bottomBar = bottomBar,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding()) { content() }
    }
}
