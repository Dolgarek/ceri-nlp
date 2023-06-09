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
    case .stop:
        soapMessage = "<StopMusic/>"
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
    case stop
    case playSong(String)
    case playArtist(String)
    case playSongAndArtist(song: String, artist: String)
}

var soapEnvelope = ""

func requestParser(request: HttpRequest) -> HttpResponse {
    let data = Data(request.body)
    let parser = XMLParser(data: data)
    let delegate = XMLDelegate()
    parser.delegate = delegate
    parser.parse()
    
    let textData = delegate.text
    print("Transcription \(type(of: textData)) : \(textData)")
    
    processCommand(text: textData)
    
    return HttpResponse.raw(200, "OK", ["Content-Type": "application/xml"], { writer in
        guard let data = soapEnvelope.data(using: .utf8) else {
            print("ERROR 500")
            return
        }
        try writer.write(data)
    })
}

server.POST["/action"] = { request in
    return requestParser(request: request)
}

func processCommand(text: String) -> String {
    
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
    var processingCommand = true

    tagger.enumerateTags(in: wholeText, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
        let word = String(text[range]).lowercased()
        
        if processingCommand {
            if word == "stop" || word == "arrête" || word == "coupe" || word == "couper" || word == "arrêter" || word == "stopper" {
                currentCommand = word
                processingCommand = false
            }
            if word == "joue" || word == "jouer" || word == "lancer" || word == "lance" || word == "écoute" || word == "écouter" {
                currentCommand = "lance"
                processingCommand = false
            }
            if word == "reprendre" || word == "continue" || word == "continuer" || word == "reprend" {
                currentCommand = "reprendre"
                processingCommand = false
            }
            if word == "pause" {
                currentCommand = word
                processingCommand = false
            }
            //Gérer unknown
        } else {
            if let tag = tag {
                switch tag {
                case .verb, .noun, .adjective, .adverb, .preposition, .otherWord:
                    if word == "de" {
                        processingArtist = true
                    }
                    if processingArtist {
                        currentArtist = word
                    } else {
                        currentSong += " " + word
                        currentSong = currentSong.trimmingCharacters(in: .whitespaces)
                    }
                default:
                    break
                }
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
    case "pause":
        musicAction = .pause
        print("4")
    case "stop", "stopper", "coupe", "couper", "arrête", "arrêter":
        musicAction = .stop
        print("5")
    case "reprendre", "continuer":
        musicAction = .resume
        print("6")
    case "artiste":
        musicAction = .playArtist(currentArtist)
        print("7")
    default:
        break
    }
    
    var soapMessage = ""
        switch musicAction {
        case .play:
            soapMessage = "<PlayMusic/>"
        case .pause:
            soapMessage = "<PauseMusic/>"
        case .stop:
            soapMessage = "<StopMusic/>"
        case .resume:
            soapMessage = "<ResumeMusic/>"
        case .playSong(let song):
            soapMessage = "<PlaySong><song>\(song)</song></PlaySong>"
        case .playArtist(let artist):
            soapMessage = "<PlayArtist><artist>\(artist)</artist></PlayArtist>"
        case .playSongAndArtist(let song, let artist):
            soapMessage = "<PlaySongAndArtist><song>\(song)</song><artist>\(artist)</artist></PlaySongAndArtist>"
        default:
            break
        }

        soapEnvelope = """
            <?xml version="1.0" encoding="utf-8"?>
            <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
              <soap:Body>
                \(soapMessage)
              </soap:Body>
            </soap:Envelope>
            """
    
    return soapEnvelope
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

tag(text: "Joue Thunderstruck de AC/DC")
//let command = "Joue Thunderstruck de AC/DC"
let command = "Joue Thunderstruck de AC/DC"
print(processCommand(text: command))

/*if let action = processCommand(text: command) {
    //performAction(action)
}*/

/*do {
    try server.start(45877, forceIPv4: true)
    
    print("Server is running on http://192.168.1.12:45877/")
    RunLoop.main.run()
} catch {
    print("Error starting server: \(error)")
}*/
