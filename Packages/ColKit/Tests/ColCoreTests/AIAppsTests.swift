import Foundation
import Testing
@testable import ColCore

struct AIAppsTests {
    @Test func appsAreFoundByAnyOfTheirIdentifiers() {
        #expect(AICatalog.app(bundleIdentifier: "com.openai.chat")?.id == "chatgpt")
        #expect(AICatalog.app(bundleIdentifier: "com.openai.codex")?.id == "chatgpt")
        #expect(AICatalog.app(bundleIdentifier: "com.electron.ollama")?.server == .ollama)
        #expect(AICatalog.app(bundleIdentifier: "com.apple.Safari") == nil)
    }

    @Test func catalogIdentifiersNeverRepeat() {
        let identifiers = AICatalog.apps.flatMap(\.bundleIdentifiers)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(Set(AICatalog.apps.map(\.id)).count == AICatalog.apps.count)
    }

    @Test func typedAddressesAreCompleted() {
        #expect(ModelServer.address(from: "192.168.1.20", kind: .ollama)?.absoluteString == "http://192.168.1.20:11434")
        #expect(ModelServer.address(from: "https://ai.example.com/", kind: .openAI)?.absoluteString == "https://ai.example.com:8000")
        #expect(ModelServer.address(from: "http://studio.local:1234", kind: .lmStudio)?.absoluteString == "http://studio.local:1234")
        #expect(ModelServer.address(from: "  ", kind: .ollama) == nil)
        #expect(ModelServer.address(from: "ftp://box", kind: .ollama) == nil)
    }

    @Test func localServersAreToldApart() {
        #expect(ModelServer(name: "a", kind: .ollama, address: URL(string: "http://localhost:11434")!).isLocal)
        #expect(!ModelServer(name: "b", kind: .ollama, address: URL(string: "http://192.168.1.20:11434")!).isLocal)
    }

    @Test func readsOllama() {
        let tags = Data(#"{"models":[{"name":"llama3.2:3b","size":2019393189},{"name":"qwen3:8b"}]}"#.utf8)
        #expect(ModelServerReply.ollamaModels(tags) == ["llama3.2:3b", "qwen3:8b"])
        let ps = Data(#"{"models":[{"name":"qwen3:8b","size_vram":5800000000,"expires_at":"2026-10-01T20:00:00Z"}]}"#.utf8)
        #expect(ModelServerReply.ollamaLoaded(ps) == [LoadedModel(name: "qwen3:8b", memory: 5_800_000_000)])
        #expect(ModelServerReply.ollamaModels(Data("not json".utf8)) == nil)
    }

    @Test func readsLMStudioWithoutEmbeddings() throws {
        let data = Data(#"{"data":[{"id":"gemma-3-12b","state":"loaded","type":"llm"},{"id":"nomic-embed","state":"not-loaded","type":"embeddings"},{"id":"mistral-7b","state":"not-loaded","type":"llm"}]}"#.utf8)
        let reply = try #require(ModelServerReply.lmStudioModels(data))
        #expect(reply.models == ["gemma-3-12b", "mistral-7b"])
        #expect(reply.loaded == [LoadedModel(name: "gemma-3-12b")])
    }

    @Test func readsLlamaCppSlotsAndOpenAIModels() {
        #expect(ModelServerReply.llamaCppGenerating(Data(#"[{"id":0,"is_processing":false},{"id":1,"is_processing":true}]"#.utf8)) == true)
        #expect(ModelServerReply.llamaCppGenerating(Data(#"[{"id":0,"is_processing":false}]"#.utf8)) == false)
        #expect(ModelServerReply.openAIModels(Data(#"{"object":"list","data":[{"id":"gpt-oss-20b"}]}"#.utf8)) == ["gpt-oss-20b"])
    }
}
