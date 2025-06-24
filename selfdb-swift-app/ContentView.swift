//
//  ContentView.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var manager = SelfDBManager()
    @State private var showAuthModal   = false
    @State private var showCreateTopic = false

    var body: some View {
        NavigationView {
            TopicListView(
                selfDBManager: manager,
                onShowAuthModal: { showAuthModal = true },
                onCreateTopic:  { showCreateTopic = true }
            )
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showAuthModal) {
            AuthenticationView(
                isPresented: $showAuthModal,
                selfDBManager: manager
            )
        }
        .fullScreenCover(isPresented: $showCreateTopic) {
            CreateTopicView(
                isPresented: $showCreateTopic,
                selfDBManager: manager,
                onTopicAdded: { _ in } // list auto-updates via manager
            )
        }
        .task {
            // DEBUG quick test – prints once on launch
            #if DEBUG
            await manager.fetchTopics()
            print("📋 Topics:", manager.topics.first ?? "none")
            if let first = manager.topics.first, let topicId = first.id {
                let comments = await manager.fetchCommentsForTopic(topicId)
                print("💬 \(comments.count) comments loaded for first topic")
            }
            #endif
        }
    }
}

#Preview { ContentView() }
