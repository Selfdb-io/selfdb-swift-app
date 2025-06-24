# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a SwiftUI iOS application demonstrating SelfDB as a backend-as-a-service. It's a discussion board app with topics, comments, file attachments, and user authentication.

## Build and Development Commands

### Xcode (Recommended)
```bash
# Open the project in Xcode
open selfdb-swift-app.xcodeproj

# Build and run: Press Cmd+R in Xcode
```

### Command Line
```bash
# Build the project
xcodebuild -project selfdb-swift-app.xcodeproj -scheme selfdb-swift-app build

# Build for Debug configuration
xcodebuild -project selfdb-swift-app.xcodeproj -scheme selfdb-swift-app -configuration Debug build

# Clean build
xcodebuild -project selfdb-swift-app.xcodeproj -scheme selfdb-swift-app clean

# Build and run on simulator
xcodebuild -project selfdb-swift-app.xcodeproj -scheme selfdb-swift-app -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## Architecture

### MVVM with Centralized State Management
- **SelfDBManager**: Central manager class that handles all SelfDB operations and state management
  - Located at: `selfdb-swift-app/SelfDBManager.swift`
  - Uses `@Published` properties for reactive UI updates
  - All data operations go through this manager

### Key Architectural Patterns
1. **SwiftUI + Combine**: Declarative UI with reactive state management
2. **Async/Await**: All network operations use modern Swift concurrency
3. **Repository Pattern**: SelfDBManager encapsulates all data operations
4. **Singleton Pattern**: Single shared instance of SelfDBManager

### Data Flow
1. Views observe SelfDBManager via `@StateObject` or `@ObservedObject`
2. User actions trigger async methods on SelfDBManager
3. Manager updates `@Published` properties
4. SwiftUI automatically updates the UI

## Project Structure

```
selfdb-swift-app/
├── Core/
│   ├── selfdb_swift_appApp.swift    # App entry point
│   ├── ContentView.swift            # Main container
│   └── SelfDBManager.swift          # Central state manager
├── Models/
│   └── DiscussionModels.swift       # Topic & Comment models
├── Views/
│   ├── TopicListView.swift          # Home screen
│   ├── TopicDetailView.swift        # Topic details
│   ├── CreateTopicView.swift        # Create/edit topics
│   ├── AddCommentView.swift         # Add/edit comments
│   ├── AuthenticationView.swift     # Login/register
│   └── FileViewer.swift             # File preview
└── Utils/
    ├── DateFormatting.swift         # Date utilities
    ├── Extensions.swift             # Swift extensions
    └── BackwardCompatibility.swift  # iOS compatibility
```

## Key Dependencies

- **SelfDB iOS SDK** (v0.0.1): Backend SDK via Swift Package Manager
- **Minimum iOS**: 16.0
- **Swift**: 5.9+
- **Xcode**: 14.0+

## Database Setup

Create the required tables in your SelfDB instance:

```sql
-- Create topics table
CREATE TABLE topics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    author_name TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id),
    file_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create comments table
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id UUID REFERENCES topics(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    author_name TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id),
    file_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX idx_comments_topic_id ON comments(topic_id);
CREATE INDEX idx_topics_created_at ON topics(created_at DESC);
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);
```

## User Permissions

- **Guest Users**: Can browse and read all topics and comments (no auth required)
- **Authenticated Users**: Can create topics/comments, edit/delete their own content, upload files
- **Superusers**: Full moderation capabilities - can edit/delete any content

## Important Development Notes

1. **No Test Suite**: The project currently has no unit or UI tests. Testing is manual through the app.

2. **SelfDB Configuration**: Update credentials in `SelfDBManager.swift:14-18`
   ```swift
   private let config = SelfDBConfig(
       apiURL: URL(string: "http://localhost:8000/api/v1")!,
       storageURL: URL(string: "http://localhost:8001")!,
       apiKey: "your-anon-key-here"
   )
   ```

3. **File Storage**: Uses a public bucket named "discussion" for all file attachments (automatically created on first use)

4. **Authentication**: Handled entirely by SelfDB SDK with secure token management

5. **Error Handling**: All async operations use proper error handling with user-friendly messages

6. **Thread Safety**: UI updates use `@MainActor` for thread-safe operations

7. **Performance**: Implements URL caching and concurrent file preloading for better performance

8. **File Handling Features**:
   - Smart URL caching to minimize API calls
   - Concurrent file URL preloading
   - MIME type detection for various file types
   - Automatic cleanup of orphaned files when content is deleted

9. **Real-time Updates**:
   - Topics automatically refresh after modifications
   - Comment counts update dynamically
   - Pull-to-refresh on all list views