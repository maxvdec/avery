use drvpack::get_options;

fn main() {
    let options = get_options();

    // Demonstrate accessing the options
    println!(
        "Driver: {} v{}.{}.{}",
        options.driver_name(),
        options.driver_version()[0],
        options.driver_version()[1],
        options.driver_version()[2]
    );
    println!("Description: {}", options.driver_description());
    println!("Manufacturer ID: 0x{:X}", options.manufacturer());
    println!("Device ID: 0x{:X}", options.device_id());
    println!("Subsystem ID: 0x{:X}", options.subsystem());
    println!("Driver Type: {}", options.driver_type());

    println!("Driver packed!");
}
