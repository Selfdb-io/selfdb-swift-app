//
//  ContentView.swift
//  Self-Social
//

import SwiftUI
import SelfDB

struct ContentView: View {
    @EnvironmentObject var db: SelfDBManager
    
    var body: some View {
        Group {
            if db.isInitializing {
                LoadingView()
            } else if db.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .task {
            await db.initializeAuth()
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .foregroundColor(.secondary)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var db: SelfDBManager
    @State private var selectedTab = 0
    @State private var showCreatePost = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(showCreatePost: $showCreatePost)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            
            ProfileView(userId: db.currentUser?.id ?? "")
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(1)
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SelfDBManager.shared)
}
