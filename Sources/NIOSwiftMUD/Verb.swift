//
//  File.swift
//  
//
//  Created by Maarten Engels on 01/11/2021.
//

import Foundation

enum Verb {
    case illegal
    case empty
    
    // known commands
    case close
    case createUser(username: String, password: String)
    
    static func expectedWordCount(verb: String) -> Int {
        switch verb.uppercased() {
        case "CREATE_USER":
            return 3
        default:
            return 1
        }
    }
    
    static func createVerb(from str: String) -> Verb {
        let trimmedString = str.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let parts = trimmedString.split(separator: " ")
        
        guard parts.count >= 1 && parts[0] != "" else {
            return .empty
        }
        
        guard parts.count >= Self.expectedWordCount(verb: String(parts[0])) else {
            return .illegal
        }
        
        switch parts[0].uppercased() {
        case "CLOSE":
            return .close
        case "CREATE_USER":
            return .createUser(username: String(parts[1]), password: String(parts[2]))
        default:
            return .illegal
        }
    }
}
