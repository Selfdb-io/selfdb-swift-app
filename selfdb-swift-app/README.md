# SelfDB Swift Sample App

A feature-rich discussion board iOS application demonstrating the capabilities of [SelfDB](https://selfdb.io) as a backend-as-a-service (BaaS) solution. This sample app showcases authentication, real-time data management, file storage, and more using the SelfDB Swift SDK.

## Features

### Core Functionality
- **Discussion Topics**: Create, read, update, and delete discussion topics
- **Comments System**: Full commenting system with nested conversations
- **File Attachments**: Support for images, videos, PDFs, and other file types on both topics and comments
- **User Authentication**: Secure user registration and login
- **Real-time Updates**: Automatic refresh and synchronization of content

### User Interface
- **Modern SwiftUI Design**: Clean, intuitive interface following iOS design guidelines
- **Responsive Layout**: Optimized for various iPhone screen sizes
- **Image & Media Preview**: In-app preview for attached images and files
- **Pull-to-Refresh**: Refresh content with a simple gesture
- **Loading States**: Smooth loading indicators and error handling

### Technical Features
- **Offline Caching**: Smart file URL caching for improved performance
- **Concurrent Operations**: Efficient parallel data fetching
- **Error Handling**: Comprehensive error states and user feedback
- **State Management**: Centralized state management with `@StateObject` and `ObservableObject`

## Architecture

### Project Structure
```
selfdb-swift-app/
├── SelfDBManager.swift         # Core manager handling all SelfDB operations
├── Models/
│   └── DiscussionModels.swift  # Data models (Topic, Comment)
├── Views/
│   ├── ContentView.swift       # Main app container
│   ├── TopicListView.swift     # Home screen with topic list
│   ├── TopicDetailView.swift   # Individual topic with comments
│   ├── CreateTopicView.swift   # Create/edit topics
│   ├── AddCommentView.swift    # Add/edit comments
│   ├── AuthenticationView.swift # Login/register screen
│   └── FileViewer.swift        # File preview component
├── Utils/
│   ├── DateFormatting.swift    # Date formatting utilities
│   └── Extensions.swift        # Swift extensions
└── BackwardCompatibility.swift # iOS version compatibility
```

### Key Components

#### SelfDBManager
The central manager class that handles all interactions with SelfDB:
- **Authentication**: User registration, login, logout, and session management
- **Topics Management**: CRUD operations for discussion topics
- **Comments Management**: CRUD operations for comments
- **File Storage**: Upload, download, and deletion of file attachments
- **State Management**: Published properties for reactive UI updates

#### Data Models
- **Topic**: Represents a discussion topic with title, content, author, and optional file attachment
- **Comment**: Represents a comment on a topic with content, author, and optional file attachment
- **User**: User profile information from SelfDB authentication

#### Views
- **TopicListView**: Main screen displaying all topics with search functionality
- **TopicDetailView**: Shows a single topic with its comments and interaction options
- **CreateTopicView**: Form for creating new topics or editing existing ones
- **AddCommentView**: Form for adding or editing comments
- **AuthenticationView**: Handles user login and registration
- **FileViewer**: Intelligent file preview component supporting images, videos, and documents

## Setup Instructions

### Prerequisites
- Xcode 14.0 or later
- iOS 16.0+ deployment target
- SelfDB account and API credentials

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd selfdb-swift-app
   ```

2. **Install Dependencies**
   
   The project uses the SelfDB Swift SDK. Make sure it's properly imported in your project.

3. **Configure SelfDB**
   
   Update the configuration in `SelfDBManager.swift`:
   ```swift
   private let config = SelfDBConfig(
       apiURL: URL(string: "http://localhost:8000/api/v1")!,
       storageURL: URL(string: "http://localhost:8001")!,
       apiKey: "your-anon-key-here"
   )
   ```

4. **Database Setup**
   
   Create the required tables in your SelfDB instance by running these SQL commands:
   
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

5. **Storage Bucket**
   
   The app uses a public bucket named "discussion" for file storage. This is automatically created on first use.

6. **Run the App**
   
   Open `selfdb-swift-app.xcodeproj` in Xcode and run the project on your simulator or device.

## Usage

### Guest Users
- Browse and read all topics and comments
- No authentication required for viewing content

### Authenticated Users
- Create new topics with optional file attachments
- Comment on existing topics
- Edit or delete their own topics and comments
- Upload images, videos, PDFs, and other files

### Superusers
- Edit or delete any topic or comment
- Full moderation capabilities

## Key Features Implementation

### File Handling
The app implements sophisticated file handling:
- Smart URL caching to minimize API calls
- Concurrent file URL preloading for better performance
- Support for various file types with appropriate MIME type detection
- Automatic cleanup of orphaned files when content is deleted

### Real-time Updates
- Topics automatically refresh after any modification
- Comment counts update dynamically
- Pull-to-refresh on all list views

### Error Handling
- Network error recovery
- User-friendly error messages
- Retry mechanisms for failed operations

## Security Considerations

- API keys should be stored securely (not hardcoded in production)
- File uploads are validated by type and size
- User authentication tokens are managed by the SelfDB SDK
- Public bucket is used for demo purposes; consider private buckets for sensitive content

## Contributing

Feel free to submit issues and enhancement requests!

## License

This sample app is provided as-is for demonstration purposes. Please refer to the license file for more information.

## Acknowledgments

Built with [SelfDB](https://selfdb.dev) - The modern backend-as-a-service platform for Swift developers.