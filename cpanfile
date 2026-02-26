
requires "Parallel::ForkManager"              => 0;
requires "Sys::Info"                          => 0;
recommends "Sys::Statistics::Linux::MemStats" => 0;

on "test" => sub {
        requires "Test2::V0"                 => 0;
};
