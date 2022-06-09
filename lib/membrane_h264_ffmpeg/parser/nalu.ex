defmodule Membrane.H264.FFmpeg.Parser.NALu do
  @moduledoc false

  # See https://yumichan.net/video-processing/video-compression/introduction-to-h264-nal-unit/
  @nalu_types %{
                0 => :unspecified,
                1 => :non_idr,
                2 => :part_a,
                3 => :part_b,
                4 => :part_c,
                5 => :idr,
                6 => :sei,
                7 => :sps,
                8 => :pps,
                9 => :aud,
                10 => :end_of_seq,
                11 => :end_of_stream,
                12 => :filler_data,
                13 => :sps_extension,
                14 => :prefix_nal_unit,
                15 => :subset_sps,
                (16..18) => :reserved,
                19 => :auxiliary_non_part,
                20 => :extension,
                (21..23) => :reserved,
                (24..31) => :unspecified
              }
              |> Enum.flat_map(fn
                {k, v} when is_integer(k) -> [{k, v}]
                {k, v} -> Enum.map(k, &{&1, v})
              end)
              |> Map.new()

  @typedoc """
  Type describing options that can be passed to `parse/2` function.

  - discard_partial_nalu? - if enabled, the last NALU will be discarded, unless the delimiter (001 or 0001) sequence is present at the end.
  Otherwise, the parser will attempt to parse all NALUs
  """
  @type parse_option_t() :: {:discard_partial_nalu?, boolean()}
  @type parse_options_t() :: list(parse_option_t())

  @spec parse(binary, parse_options_t()) :: {list, %{h264: any}}
  def parse(access_unit, options \\ []) do
    {nalus, au_info} =
      access_unit
      |> extract_nalus(options)
      |> Enum.map_reduce(%{key_frame?: false}, &parse_nalu(&1, &2, access_unit))

    nalus =
      nalus
      |> List.update_at(0, &put_in(&1, [:metadata, :h264, :new_access_unit], au_info))
      |> List.update_at(-1, &put_in(&1, [:metadata, :h264, :end_access_unit], true))

    {nalus, %{h264: au_info}}
  end

  defp extract_nalus(access_unit, options) do
    access_unit
    |> :binary.matches([<<0, 0, 0, 1>>, <<0, 0, 1>>])
    |> Enum.chunk_every(
      2,
      1,
      if(Keyword.get(options, :discard_partial_nalu?, false),
        do: :discard,
        else: [{byte_size(access_unit), nil}]
      )
    )
    |> Enum.map(fn [{from, prefix_len}, {to, _}] ->
      len = to - from
      %{prefixed_poslen: {from, len}, unprefixed_poslen: {from + prefix_len, len - prefix_len}}
    end)
  end

  defp parse_nalu(nalu, access_unit_info, access_unit) do
    <<0::1, _nal_ref_idc::unsigned-integer-size(2), nal_unit_type::unsigned-integer-size(5),
      _rest::bitstring>> = :binary.part(access_unit, nalu.unprefixed_poslen)

    type = @nalu_types |> Map.fetch!(nal_unit_type)

    new_au_info = if type == :idr, do: %{key_frame?: true}, else: %{}

    nalu = Map.put(nalu, :metadata, %{h264: %{type: type}})
    {nalu, Map.merge(access_unit_info, new_au_info)}
  end
end
