import Foundation

private func bundledData(_ name: String) -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
          let data = try? Data(contentsOf: url) else { fatalError("missing resource \(name).json") }
    return data
}

private struct RegionsFile: Decodable {
    let REGIONS: String
    let CITIES: String
}

private let regionsFile: RegionsFile = {
    do { return try JSONDecoder().decode(RegionsFile.self, from: bundledData("regions")) }
    catch { fatalError("regions.json: \(error)") }
}()

/// "admin\tcountry" per line; a city's region column indexes into it.
public let bundledRegions: String = regionsFile.REGIONS
/// "name\tregionIndex\tzh" per line, most populous first.
public let bundledCities: String = regionsFile.CITIES

public let bundledPlaybooks: [Playbook] = {
    do { return try JSONDecoder().decode([Playbook].self, from: bundledData("playbooks")) }
    catch { fatalError("playbooks.json: \(error)") }
}()

func bundledResource(_ name: String) -> Data { bundledData(name) }
