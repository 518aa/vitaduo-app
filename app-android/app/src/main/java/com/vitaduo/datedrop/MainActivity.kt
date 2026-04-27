package com.vitaduo.datedrop

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.vitaduo.datedrop.network.NetworkManager
import com.vitaduo.datedrop.ui.theme.DateDropTheme
import com.vitaduo.datedrop.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NetworkManager.init(applicationContext)
        setContent {
            DateDropTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    AppNavigation()
                }
            }
        }
    }
}

@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val startDestination = if (NetworkManager.hasToken()) "main" else "intro"

    NavHost(navController = navController, startDestination = startDestination) {
        composable("intro") { IntroScreen(navController) }
        composable("register") { RegisterScreen(navController) }
        composable("questionnaire") { QuestionnaireScreen(navController) }
        composable("main") { MainScreen(navController) }
        composable("chat/{matchId}") { backStackEntry ->
            val matchId = backStackEntry.arguments?.getString("matchId")?.toIntOrNull() ?: 0
            ChatDetailScreen(navController, matchId)
        }
        composable("rating/{matchId}") { backStackEntry ->
            val matchId = backStackEntry.arguments?.getString("matchId")?.toIntOrNull() ?: 0
            RatingScreen(navController, matchId)
        }
        composable("profile") { ProfileScreen(navController) }
        composable("paywall") { PaywallScreen(navController) }
        composable("terms") { TermsScreen(navController) }
    }
}
