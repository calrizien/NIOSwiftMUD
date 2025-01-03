//
//  CommandTests.swift
//  
//
//  Created by Maarten Engels on 20/05/2023.
//

import Foundation
import XCTest
@testable import NIOSwiftMUD

class CommandTests: XCTestCase {
    
    // MARK: Helpders
    override func setUp() {
        User.persist = false
        Room.persist = false
        Door.persist = false
    }

    struct MockSession: Session {
        let id: UUID
        var playerID: UUID?
        var shouldClose = false
        var currentString = ""
        
        init() {
            self.id = UUID()
        }
    }

    // MARK: Generic Tests
    func test_commands_thatRequireLogin_failWhenNotLoggedIn() async {
        let session = MockSession()
        let commandsThatRequireLogin = MudCommandFactory().allCommands.filter { $0.requiresLogin }

        for commandType in commandsThatRequireLogin {
            let arguments = Array(repeating: "north", count: commandType.expectedArgumentCount)
            let command = commandType.create(arguments, session: session)

            guard let result = await command?.execute() else {
                XCTFail("Command \(commandType) should not be nil.")
                return
            }

            guard result.count > 0 else {
                XCTFail("Expected at least 1 MudResponse.")
                return
            }

            XCTAssertEqual(result[0].message, command?.couldNotFindPlayerMessage ?? "")
        }
    }
    
    // MARK: HelpCommand
    func test_HelpCommand() async {
        let session = MockSession()
        let command = HelpCommand(session: session)
        
        let result = await command.execute()
        
        XCTAssertEqual(result.first?.session.id, session.id)
        XCTAssertEqual(result.first?.message, HelpCommand.HELP_STRING)
    }
    
    // MARK: CloseCommand
    func test_CloseCommand() async {
        let session = MockSession()
        let command = CloseCommand(session: session)
        
        XCTAssertFalse(session.shouldClose)
        
        let result = await command.execute()
        
        XCTAssertTrue(result.first?.session.shouldClose ?? false)
    }
    
    // MARK: CreateUserCommand
    func test_CreateUserCommand() async {
        let session = MockSession()
        
        let testusername = "Testuser_\(UUID())"
        let command = CreateUserCommand(session: session, username: testusername, password: "password")
        
        let existingUser = await User.first(username: testusername)
        XCTAssertNil(existingUser)
        
        let result = await command.execute()
        
        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            return
        }
        
        XCTAssertEqual(result[0].session.id, session.id)
        
        guard let existingUserAfterSave = await User.first(username: testusername) else {
            XCTFail("Should have found recently created testuser: \(testusername)")
            return
        }
        
        XCTAssertEqual(result[0].session.playerID, existingUserAfterSave.id)
        XCTAssertEqual(result[0].message, "Welcome, \(testusername)!")
    }
    
    func test_CreateUserCommand_fails_withExistingUsername() async {
        let session = MockSession()
        
        let testusername = "Testuser_\(UUID())"
        
        let testuser = User(username: testusername, password: "password")
        await testuser.save()
        
        let command = CreateUserCommand(session: session, username: testusername, password: "123456")
        
        let result = await command.execute()
        
        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            return
        }
        
        XCTAssertEqual(result[0].session.id, session.id)
        XCTAssertNil(result[0].session.playerID)
        XCTAssertEqual(result[0].message, "Error creating user: usernameAlreadyTaken")
    }
    
    // MARK: LoginUserCommand
    func test_LoginUserCommand() async {
        let session = MockSession()
        
        let testusername = "Testuser_\(UUID())"
        let testPassword = "FooBar123"
        let testuser = User(username: testusername, password: testPassword)
        await testuser.save()
        
        let command = LoginCommand(session: session, username: testusername, password: testPassword)
        
        let result = await command.execute()
        
        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            return
        }
        
        XCTAssertEqual(result[0].session.id, session.id)
        XCTAssertEqual(result[0].session.playerID, testuser.id)
        XCTAssertEqual(result[0].message, "Welcome back, \(testusername)!")
    }
    
    func test_LoginUserCommand_fails_withWrongPassword() async {
        let session = MockSession()
        
        let testusername = "Testuser_\(UUID())"
        let testPassword = "FooBar123"
        let testuser = User(username: testusername, password: testPassword)
        await testuser.save()
        
        let command = LoginCommand(session: session, username: testusername, password: "invalid"+testPassword)
        
        let result = await command.execute()
        
        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            return
        }
        
        XCTAssertEqual(result[0].session.id, session.id)
        XCTAssertNil(result[0].session.playerID)
        XCTAssertEqual(result[0].message, "Error logging in user: passwordMismatch")
    }
    
    // MARK: LookCommand
    func test_LookCommand() async {
        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = Room.STARTER_ROOM_ID // Make sure the player is in the starter room.
        session.playerID = testuser.id // Simulate player successfully logged in.
        
        await testuser.save()
        
        let command = LookCommand(session: session)
        
        let result = await command.execute()
        
        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            return
        }
        
        guard let defaultRoom = await Room.find(Room.STARTER_ROOM_ID) else {
            XCTFail("Should have found a starter room.")
            return
        }
        
        let compareString = String(defaultRoom.name)
        let receivedString = String(result[0].message.prefix(compareString.count))
        XCTAssertEqual(receivedString, compareString)
    }
    
    // MARK: GoCommand
    func test_GoCommand() async {
        let roomCount = await Room.count()
        XCTAssertGreaterThan(roomCount, 1)

        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = Room.STARTER_ROOM_ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        
        await testuser.save()

        guard let room = await Room.find(testuser.currentRoomID) else {
            XCTFail("Should have found a room for the player.")
            return
        }
        
        guard room.exits.count > 0 else {
            XCTFail("Should have found at least 1 exit in the room.")
            return
        }   

        guard let firstExit = room.exits.first else {
            XCTFail("Should have found at least 1 exit in the room.")
            return
        }
        
        // Make sure the exit is passable, by opening any door if one exists.
        if var door = await Door.find(firstExit.doorID) {
            door.isOpen = true
            await door.save()
            print("Opened door \(door.id).")
        }

        let command = GoCommand(session: session, direction: room.exits[0].direction)

        let result = await command.execute()

        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            await Room.storage.reloadStorage()
            return
        }

        guard let updatedPlayer = await User.find(session.playerID) else {
            XCTFail("Player should have been found.")
            return
        }
        XCTAssertEqual(updatedPlayer.currentRoomID, room.exits[0].targetRoomID)
    }

    func test_GoCommand_fails_ifDoorIsClosed() async {
        let closedDoor = Door(id: UUID(), isOpen: false)
        
        let room1ID = UUID()
        let room2ID = UUID()

        let room1 = Room(id: room1ID, name: "Room 1", description: "Room 1", exits: [Exit(direction: .North, targetRoomID: room2ID, doorID: closedDoor.id)])
        let room2 = Room(id: room2ID, name: "Room 2", description: "Room 2", exits: [Exit(direction: .South, targetRoomID: room1ID, doorID: closedDoor.id)])

        await room1.save()
        await room2.save()

        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = room1ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        
        await testuser.save()

        let command = GoCommand(session: session, direction: .North)

        let result = await command.execute()

        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            await Room.storage.reloadStorage()
            return
        }

        guard let updatedPlayer = await User.find(session.playerID) else {
            XCTFail("Player should have been found.")
            return
        }
        XCTAssertEqual(result[0].message, "The exit is impassable.")
        XCTAssertEqual(updatedPlayer.currentRoomID, room1ID)
    }

    func test_GoCommand_fails_ifThereIsNotExitInDirection() async {
        let closedDoor = Door(id: UUID(), isOpen: false)
        
        let room1ID = UUID()
        let room2ID = UUID()

        let room1 = Room(id: room1ID, name: "Room 1", description: "Room 1", exits: [Exit(direction: .North, targetRoomID: room2ID, doorID: closedDoor.id)])
        let room2 = Room(id: room2ID, name: "Room 2", description: "Room 2", exits: [Exit(direction: .South, targetRoomID: room1ID, doorID: closedDoor.id)])

        await room1.save()
        await room2.save()

        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = room1ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        
        await testuser.save()

        let command = GoCommand(session: session, direction: .West)

        let result = await command.execute()

        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            await Room.storage.reloadStorage()
            return
        }

        guard let updatedPlayer = await User.find(session.playerID) else {
            XCTFail("Player should have been found.")
            return
        }
        XCTAssertEqual(result[0].message, "No exit found in direction \(command.direction).")
        XCTAssertEqual(updatedPlayer.currentRoomID, room1ID)
    }
    
    // MARK: OpenDoorCommand
    func test_openDoor() async {
        let closedDoor = Door(id: UUID(), isOpen: false)
        await closedDoor.save()
        
        let room1ID = UUID()
        let room2ID = UUID()

        let room1 = Room(id: room1ID, name: "Room 1", description: "Room 1", exits: [Exit(direction: .North, targetRoomID: room2ID, doorID: closedDoor.id)])
        let room2 = Room(id: room2ID, name: "Room 2", description: "Room 2", exits: [Exit(direction: .South, targetRoomID: room1ID, doorID: closedDoor.id)])

        await room1.save()
        await room2.save()

        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = room1ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        
        await testuser.save()

        let command = OpenDoorCommand(session: session, direction: .North)

        let result = await command.execute()

        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            return
        }

        guard let updatedDoor = await Door.find(closedDoor.id) else {
            XCTFail("Door should have been found.")
            return
        }

        guard updatedDoor.isOpen else {
            XCTFail("Door should have been opened.")
            return
        }
    }

    func test_openDoor_fails_ifDoorIsAlreadyOpen() async {
        let openDoor = Door(id: UUID(), isOpen: true)
        await openDoor.save()
        
        let room1ID = UUID()
        let room2ID = UUID()

        let room1 = Room(id: room1ID, name: "Room 1", description: "Room 1", exits: [Exit(direction: .North, targetRoomID: room2ID, doorID: openDoor.id)])
        let room2 = Room(id: room2ID, name: "Room 2", description: "Room 2", exits: [Exit(direction: .South, targetRoomID: room1ID, doorID: openDoor.id)])

        await room1.save()
        await room2.save()

        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = room1ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        
        await testuser.save()

        let command = OpenDoorCommand(session: session, direction: .North)

        let result = await command.execute()

        guard result.count > 0 else {
            XCTFail("Expected at least 1 MudResponse.")
            return
        }

        XCTAssertEqual(result[0].message, "Door in direction \(command.direction) is already open.")
    }
    
    // MARK: SayCommand
    func test_SayCommand() async {
        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = Room.STARTER_ROOM_ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        await testuser.save()

        var session2 = MockSession()
        var testuser2 = User(username: "testuser_\(UUID())", password: "String")
        testuser2.currentRoomID = Room.STARTER_ROOM_ID
        session2.playerID = testuser2.id
        SessionStorage.replaceOrStoreSessionSync(session2)
        await testuser2.save()

        let command = SayCommand(session: session, sentence: "Hello World!")
        
        let result = await command.execute()

        guard result.count > 1 else {
            XCTFail("Expected at least 2 MudResponses.")
            return
        }

        XCTAssertEqual(result[0].message, "You say: \(command.sentence)")
        XCTAssertEqual(result[1].message, "\(testusername) says: \(command.sentence)")
    }
    
    // MARK: WhisperCommand
    func test_WhisperCommand() async {
        // Lots of setup needed: create three users, including sessions
        
        // testuser1
        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = Room.STARTER_ROOM_ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        SessionStorage.replaceOrStoreSessionSync(session)
        await testuser.save()

        defer { SessionStorage.deleteSession(session) } // Let's make sure we cleanup the sessions we created.
    
        // testuser2
        var session2 = MockSession()
        let testusername2 = "Testuser2_\(UUID())"
        var testuser2 = User(username: testusername2, password: "String")
        testuser2.currentRoomID = Room.STARTER_ROOM_ID
        session2.playerID = testuser2.id
        session2.currentString = "testuser2"
        SessionStorage.replaceOrStoreSessionSync(session2)
        await testuser2.save()
        
        defer { SessionStorage.deleteSession(session2) } // Let's make sure we cleanup the sessions we created.
        
        // testuser3
        var session3 = MockSession()
        let testusername3 = "Testuser3_\(UUID())"
        var testuser3 = User(username: testusername3, password: "String")
        testuser3.currentRoomID = Room.STARTER_ROOM_ID
        session3.playerID = testuser3.id
        session3.currentString = "testuser3"
        SessionStorage.replaceOrStoreSessionSync(session3)
        await testuser3.save()
        
        defer { SessionStorage.deleteSession(session3) } // Let's make sure we cleanup the sessions we created.
        
        // the actual SUT
        let command = WhisperCommand(session: session, targetPlayerName: testusername3, message: "For your ears only")
        
        let result = await command.execute()
                
        // Validate the results
        guard result.count > 2 else {
            XCTFail("Expected at least 3 MudResponses.")
            return
        }

        XCTAssertEqual(result[0].message, "You whisper to \(testusername3): \(command.message)")
        
        guard let messageForTestUser2 = result.first(where: { $0.session.playerID == testuser2.id }) else {
            XCTFail("There should be a message for testuser2")
            return
        }
        
        guard let messageForTestUser3 = result.first(where: { $0.session.playerID == testuser3.id }) else {
            XCTFail("There should be a message for testuser3")
            return
        }
        
        XCTAssertEqual(messageForTestUser2.message, "\(testusername) whispers something to \(testuser3.username), but you can't quite make out what is said.")
        
        XCTAssertEqual(messageForTestUser3.message, "\(testusername) whispers to you: \(command.message)")
    }

    func test_WhisperCommand_returnsFunnyMessage_when_YouTargetYourself() async {
        var session = MockSession()
        let testusername = "Testuser_\(UUID())"
        var testuser = User(username: testusername, password: "password")
        testuser.currentRoomID = Room.STARTER_ROOM_ID
        session.playerID = testuser.id // Simulate player successfully logged in.
        SessionStorage.replaceOrStoreSessionSync(session)
        await testuser.save()

        defer { SessionStorage.deleteSession(session) } // Let's make sure we cleanup the sessions we created.
    
        // the actual SUT
        let command = WhisperCommand(session: session, targetPlayerName: testusername, message: "For your ears only")
        
        let result = await command.execute()
                
        // Validate the results
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].message, "Talking to yourself much, eh?")
    }
}
