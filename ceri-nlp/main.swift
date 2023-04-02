//
//  main.swift
//  ceri-nlp
//
//  Created by Théo QUEZEL-PERRON on 10/03/2023.
//

import Foundation
import NaturalLanguage
import Swifter

let server = HttpServer()

func helloWorld(request: HttpRequest) -> HttpResponse {
    let soapResponse = """
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
            <transcription>Bonjour le Monde</transcription>
        </soap:Body>
    </soap:Envelope>
    """
    return HttpResponse.raw(200, "OK", ["Content-Type": "application/xml"], { writer in
        guard let data = soapResponse.data(using: .utf8) else {
            print("ERROR 500")
            return
        }
        try writer.write(data)
    })}

server.GET["/"] = { request in
    return helloWorld(request: request)
}

func createSOAPRequest(action: MusicAction, endpoint: String) -> URLRequest? {
    let soapMessage: String

    switch action {
    case .play:
        soapMessage = "<PlayMusic/>"
    case .pause:
        soapMessage = "<PauseMusic/>"
    case .resume:
        soapMessage = "<ResumeMusic/>"
    case .playSong(let song):
        soapMessage = "<PlaySong><song>\(song)</song></PlaySong>"
    case .playArtist(let artist):
        soapMessage = "<PlayArtist><artist>\(artist)</artist></PlayArtist>"
    case .playSongAndArtist(let song, let artist):
        soapMessage = "<PlaySongAndArtist><song>\(song)</song><artist>\(artist)</artist></PlaySongAndArtist>"
    }

    let soapEnvelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            \(soapMessage)
          </soap:Body>
        </soap:Envelope>
        """

    guard let url = URL(string: endpoint) else {
        print("Invalid URL")
        return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = soapEnvelope.data(using: .utf8)
    request.addValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.addValue(String(soapEnvelope.count), forHTTPHeaderField: "Content-Length")

    return request
}

func sendSOAPRequest(request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
    let task = URLSession.shared.dataTask(with: request, completionHandler: completion)
    task.resume()
}

func tag(text: String) {
    print()
    print(text)
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = text
    let wholeText = text.startIndex..<text.endIndex
    tagger.setLanguage(.french, range: wholeText)
    let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
    tagger.enumerateTags(in: wholeText, unit: .word, scheme: .lexicalClass, options: options) {tag, range in
        print("\(text[range])->\(tag!.rawValue)")
        
        return true
    }
}

enum MusicAction {
    case play
    case pause
    case resume
    case playSong(String)
    case playArtist(String)
    case playSongAndArtist(song: String, artist: String)
}

func processCommand(text: String) -> MusicAction? {
    let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
    tagger.string = text
    let wholeText = text.startIndex..<text.endIndex
    tagger.setLanguage(.french, range: wholeText)
    let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

    var musicAction: MusicAction?
    var currentCommand: String = ""
    var currentSong: String = ""
    var currentArtist: String = ""
    var processingArtist = false

    tagger.enumerateTags(in: wholeText, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
        let word = String(text[range]).lowercased()
        
        if let tag = tag {
            switch tag {
            case .verb:
                currentCommand = word
            case .noun, .adjective, .adverb, .preposition:
                if word == "de" {
                    processingArtist = true
                }
                if processingArtist {
                    currentArtist = word
                } else {
                    currentSong += " " + word
                }
            default:
                break
            }
        }
        print(currentCommand, currentSong, currentArtist, processingArtist)
        return true
    }
    
    switch currentCommand {
    case "lancer", "lance", "jouer", "joue", "écouter", "écoute":
        if currentArtist.isEmpty {
            if currentSong == "musique" || currentSong == "chanson" {
                musicAction = .play
                print("1")
            } else {
                musicAction = .playSong(currentSong)
                print("2")
            }
        } else {
            musicAction = .playSongAndArtist(song: currentSong, artist: currentArtist)
            print("3")
        }
    case "pause", "arrêter":
        musicAction = .pause
        print("4")
    case "reprendre", "continuer":
        musicAction = .resume
        print("5")
    case "artiste":
        musicAction = .playArtist(currentArtist)
        print("6")
    default:
        break
    }
    
    return musicAction
}
func performAction(_ action: MusicAction) {
    let endpoint = "https://your-soap-server.com/soap-endpoint"

    print("ok")
    guard let request = createSOAPRequest(action: action, endpoint: endpoint) else {
        print("Failed to create SOAP request")
        return
    }
    print("ok")
    
    sendSOAPRequest(request: request) { (data, response, error) in
        if let error = error {
            print("Error: \(error)")
        } else if let data = data {
            print("SOAP Response: \(String(data: data, encoding: .utf8) ?? "")")
        }
    }
}

tag(text: "Joue trop beau de Lomepal")
//let command = "Joue Thunderstruck de AC/DC"
let command = "Joue trop beau de Lomepal"

if let action = processCommand(text: command) {
    //performAction(action)
}

do {
    try server.start(45877, forceIPv4: true)
    
    print("Server is running on http://192.168.1.12:45877/")
    RunLoop.main.run()
} catch {
    print("Error starting server: \(error)")
}
